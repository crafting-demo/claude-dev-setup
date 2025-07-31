#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, existsSync, appendFileSync, writeFileSync } from "fs";
import { execSync } from "child_process";
import os from "os";
import path from "path";

// Simplified logging - stream-json now handles detailed tool call visibility
const SESSION_STATE_FILE = path.join(os.homedir(), "cmd", "session-state.json");

function mcpLog(message, level = 'info') {
  // Only log essential messages since stream-json captures detailed tool interactions
  const prefixedMessage = `[LOCAL-MCP] ${message}`;
  
  // Log to console (captured by Claude's stream-json output)
  if (level === 'error' || level === 'startup' || level === 'warn') {
    console.log(prefixedMessage);
  }
  // Skip verbose logs - stream-json provides better visibility
}

class LocalMCPServer {
  constructor() {
    this.server = new Server({
      name: "local-mcp-server",
      version: "1.0.0"
    }, {
      capabilities: {
        tools: {}
      }
    });
    
    this.tools = [];
    this.sessions = new Map(); // Track conversation sessions for stateful tools
    this.setupRequestHandlers();
  }

  // Load session state from persistent storage
  getSessionState() {
    try {
      if (existsSync(SESSION_STATE_FILE)) {
        const content = readFileSync(SESSION_STATE_FILE, "utf-8");
        const state = JSON.parse(content);
        mcpLog(`Loaded session state with ${Object.keys(state).length} tool sessions`);
        return state;
      }
    } catch (error) {
      mcpLog(`Error loading session state: ${error.message}`);
    }
    mcpLog("Starting with empty session state");
    return {};
  }

  // Save session state to persistent storage
  saveSessionState(state) {
    try {
      writeFileSync(SESSION_STATE_FILE, JSON.stringify(state, null, 2));
      mcpLog(`Saved session state with ${Object.keys(state).length} tool sessions`);
    } catch (error) {
      mcpLog(`Error saving session state: ${error.message}`);
    }
  }

  // Get the latest session ID for the claude-target-repo project
  getLatestSessionId() {
    try {
      const cwd = process.cwd();
      mcpLog(`Getting latest session for current directory: ${cwd}`);
      
      // Use the specific Claude target repo project directory
      const projectDirName = "-home-owner-claude-target-repo";
      const projectPath = path.join(os.homedir(), ".claude", "projects", projectDirName);
      
      mcpLog(`Looking for sessions in: ${projectPath}`);
      
      if (!existsSync(projectPath)) {
        mcpLog(`No Claude sessions directory found at: ${projectPath}`);
        return null;
      }
      
      // Get the most recent session file
      const command = `ls -t "${projectPath}"/*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl 2>/dev/null || echo ""`;
      const result = execSync(command, { encoding: "utf-8", cwd }).trim();
      
      if (result) {
        mcpLog(`Found latest session ID: ${result}`);
        return result;
      } else {
        mcpLog("No session files found");
        return null;
      }
    } catch (error) {
      mcpLog(`Error getting latest session ID: ${error.message}`);
      return null;
    }
  }

  // Save the current session for a tool
  saveToolSession(toolName) {
    try {
      const sessionId = this.getLatestSessionId();
      if (sessionId) {
        const sessionState = this.getSessionState();
        const cwd = process.cwd();
        
        // Store both session ID and the working directory it was created in
        sessionState[toolName] = {
          sessionId: sessionId,
          workingDirectory: cwd,
          lastUsed: new Date().toISOString()
        };
        
        this.saveSessionState(sessionState);
        mcpLog(`Saved session ${sessionId} for tool ${toolName} in directory ${cwd}`);
        return sessionId;
      } else {
        mcpLog(`No session ID found to save for tool ${toolName}`);
        return null;
      }
    } catch (error) {
      mcpLog(`Error saving tool session: ${error.message}`);
      return null;
    }
  }

  // Get the previous session for a tool (if any)
  getToolSession(toolName) {
    try {
      const sessionState = this.getSessionState();
      const toolSession = sessionState[toolName];
      
      if (toolSession && toolSession.sessionId) {
        mcpLog(`Found previous session for ${toolName}: ${toolSession.sessionId} (from ${toolSession.workingDirectory})`);
        return toolSession;
      } else {
        mcpLog(`No previous session found for tool ${toolName}`);
        return null;
      }
    } catch (error) {
      mcpLog(`Error getting tool session: ${error.message}`);
      return null;
    }
  }

  // Properly escape shell arguments to prevent injection and parsing issues
  escapeShellArg(arg) {
    // If the argument contains only safe characters, return it as-is
    if (/^[a-zA-Z0-9._\-+=:@%\/]+$/.test(arg)) {
      return `"${arg}"`;
    }
    
    // For complex arguments, use single quotes and escape any single quotes inside
    return `'${arg.replace(/'/g, "'\"'\"'")}'`;
  }

  // Handle long or complex prompts by using stdin piping instead of shell arguments
  createPromptCommand(prompt, baseCommand) {
    try {
      // For complex prompts, use stdin piping to avoid shell escaping issues
      if (this.shouldUsePromptFile(prompt)) {
        // Use printf to handle complex prompts with proper escaping
        // This avoids shell argument length limits and special character issues
        const escapedPrompt = prompt.replace(/\\/g, '\\\\').replace(/'/g, "'\"'\"'");
        const command = `printf '%s' '${escapedPrompt}' | ${baseCommand}`;
        
        mcpLog(`Using stdin piping for complex prompt`);
        mcpLog(`Prompt length: ${prompt.length} characters`);
        mcpLog(`Base command: ${baseCommand}`);
        
        return command;
      } else {
        // For simple prompts, use direct argument passing
        return `${baseCommand} -p ${this.escapeShellArg(prompt)}`;
      }
    } catch (error) {
      mcpLog(`Error creating prompt command: ${error.message}`);
      throw error;
    }
  }

  // Clean up method no longer needed but keeping for compatibility
  cleanupPromptFile(filePath) {
    // No-op since we're not using files anymore
    mcpLog(`Cleanup called (no action needed for stdin approach)`);
  }

  // Determine if prompt should use stdin piping approach  
  shouldUsePromptFile(prompt) {
    // Use stdin piping for long prompts or prompts with complex content
    return prompt.length > 2000 || 
           prompt.includes('\n') || 
           prompt.includes('"') ||
           prompt.includes("'") ||
           prompt.includes('`') ||
           prompt.includes('$') ||
           prompt.includes('\\');
  }

  loadToolDefinitions() {
    const configPath = path.join(os.homedir(), "cmd", "local_mcp_tools.txt");
    
          // Loading tool configuration
    
          if (!existsSync(configPath)) {
        mcpLog(`Config file not found: ${configPath}`, 'warn');
        return;
      }

    try {
      const configContent = readFileSync(configPath, "utf-8");
      // Parsing tool configuration
      
      // Handle both JSON format and simple text format
      let toolsConfig;
      try {
        toolsConfig = JSON.parse(configContent);
      } catch (parseError) {
        mcpLog(`JSON parse error: ${parseError.message}`, 'error');
        return;
      }

      // The config should be an array directly, not wrapped in a "tools" property
      if (Array.isArray(toolsConfig)) {
        this.tools = toolsConfig;
        mcpLog(`Loaded ${this.tools.length} tools from array format`, 'startup');
      } else if (toolsConfig && toolsConfig.tools && Array.isArray(toolsConfig.tools)) {
        this.tools = toolsConfig.tools;
        mcpLog(`Loaded ${this.tools.length} tools from wrapped format`, 'startup');
              } else {
          mcpLog(`Invalid tool config format: expected array or object with 'tools' property`, 'error');
        }
          } catch (error) {
        mcpLog(`Error loading tool definitions: ${error.message}`, 'error');
      }
  }

  setupRequestHandlers() {
    // Handle tool listing
    this.server.setRequestHandler(ListToolsRequestSchema, async () => {
      this.loadToolDefinitions(); // Reload tools each time to pick up changes
      
      return {
        tools: this.tools.map(tool => ({
          name: tool.name,
          description: tool.description || `LLM-backed tool: ${tool.name}`,
          inputSchema: tool.inputSchema || {
            type: "object",
            properties: {
              input: {
                type: "string", 
                description: "Input for the tool"
              }
            },
            required: ["input"]
          }
        }))
      };
    });

    // Handle tool execution
    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;
      
      // Tool call details now visible via stream-json, minimal logging needed
      mcpLog(`Tool call: ${name}`);
      
      // Find the tool definition
      const tool = this.tools.find(t => t.name === name);
              if (!tool) {
          const error = `Tool not found: ${name}. Available tools: ${this.tools.map(t => t.name).join(', ')}`;
          mcpLog(`${error}`);
          throw new Error(error);
        }

      mcpLog(`Found tool definition for: ${tool.name}`);
      mcpLog(`Tool prompt: ${tool.prompt?.substring(0, 100)}...`);

      try {
        const result = await this.executeTool(tool, args);
        mcpLog(`Tool execution completed successfully`);
        mcpLog(`Result length: ${result.length} characters`);
        return {
          content: [
            {
              type: "text",
              text: result
            }
          ]
        };
              } catch (error) {
          mcpLog(`Error executing tool ${name}: ${error.message}`);
          mcpLog(`Error stack: ${error.stack}`);
          return {
          content: [
            {
              type: "text",
              text: `Error executing tool ${name}: ${error.message}`
            }
          ]
        };
      }
    });
  }

  async executeTool(tool, args) {
          // Detailed execution info now available via stream-json
    
    // Check for previous persistent session
    const previousSession = this.getToolSession(tool.name);
    
    // Build the Claude command based on tool configuration
    let claudeCommand;
    let usingPreviousSession = false;
    
    mcpLog(`Previous persistent session: ${previousSession ? previousSession.sessionId : 'none'}`);
    
    if (tool.prompt) {
      // Use the configured prompt template with dynamic parameter replacement
      let prompt = tool.prompt;
      
      // Handle double-brace templating: {{parameter_name}}
              // Processing template with provided arguments
      
             // Replace {{parameter}} with values from args
       prompt = prompt.replace(/\{\{([^}]+)\}\}/g, (match, paramName) => {
         const paramValue = args[paramName];
         if (paramValue !== undefined) {
           // Template parameter replaced
           return paramValue;
         } else {
           mcpLog(`Warning: Missing parameter {{${paramName}}}`, 'warn');
           return match; // Leave the placeholder if parameter not found
         }
       });
      
      // Using configured prompt template
      
      // Check if we should use previous persistent session or start fresh
      if (previousSession && previousSession.sessionId) {
        // Change to the directory where the previous session was created
        const originalCwd = process.cwd();
        if (previousSession.workingDirectory !== originalCwd) {
          // Changing to session directory
          process.chdir(previousSession.workingDirectory);
        }
        
        // Create command with proper prompt handling
        const baseCommand = `claude --resume ${previousSession.sessionId}`;
        claudeCommand = this.createPromptCommand(prompt, baseCommand);
        usingPreviousSession = true;
        // Resuming session
      } else {
        // Start new session 
        const baseCommand = `claude`;
        claudeCommand = this.createPromptCommand(prompt, baseCommand);
        this.sessions.set(tool.name, Date.now());
        // Starting new session
      }
    } else {
      // Default behavior: try to extract meaningful content from args or fall back to input
      let taskContent = "";
      
      // Try to extract the main parameter from the tool's inputSchema
      if (tool.inputSchema && tool.inputSchema.properties) {
        const requiredProps = tool.inputSchema.required || [];
        const mainParam = requiredProps[0]; // Use first required parameter
        
        if (mainParam && args[mainParam]) {
          taskContent = args[mainParam];
          mcpLog(`Using main parameter '${mainParam}' as task content`);
        }
      }
      
             // Fallback to generic message if no content found
       if (!taskContent) {
         taskContent = "No task content provided";
         mcpLog(`No task content found in parameters`);
       }
      
      const prompt = `Execute this task: ${taskContent}`;
      mcpLog(`Using default prompt behavior`);
      mcpLog(`Task content: ${taskContent.substring(0, 100)}...`);
      
      // Check if we should use previous persistent session or start fresh
      if (previousSession && previousSession.sessionId) {
        // Change to the directory where the previous session was created
        const originalCwd = process.cwd();
        if (previousSession.workingDirectory !== originalCwd) {
          // Changing to session directory
          process.chdir(previousSession.workingDirectory);
        }
        
        // Create command with proper prompt handling
        const baseCommand = `claude --resume ${previousSession.sessionId}`;
        claudeCommand = this.createPromptCommand(prompt, baseCommand);
        usingPreviousSession = true;
        // Resuming session
      } else {
        const baseCommand = `claude`;
        claudeCommand = this.createPromptCommand(prompt, baseCommand);
        this.sessions.set(tool.name, Date.now());
        // Starting new session
      }
    }

    try {
      // Executing Claude command
      const result = execSync(claudeCommand, {
        encoding: "utf-8",
        timeout: 900000, // 15 minute timeout (increased from 5 minutes)
        maxBuffer: 1024 * 1024 * 10 // 10MB buffer
      });
      
      // Save the session after successful execution (only if we're not using a previous session)
      if (!usingPreviousSession) {
                  // Saving new session
        this.saveToolSession(tool.name);
      } else {
        // Updated existing session
        // Update the lastUsed timestamp for the existing session
        const sessionState = this.getSessionState();
        if (sessionState[tool.name]) {
          sessionState[tool.name].lastUsed = new Date().toISOString();
          this.saveSessionState(sessionState);
        }
      }
      
              // Tool completion now tracked via stream-json
        mcpLog(`Tool completed: ${tool.name}`);
      
      return result.trim();
      
          } catch (error) {
        mcpLog(`Tool execution failed: ${tool.name} - ${error.message}`, 'error');
        
        // Clean up session if there was an error
        this.sessions.delete(tool.name);
        
        // Return a helpful error message instead of throwing
        // This allows the parent Claude to handle the error gracefully and potentially retry
        const errorResponse = {
          success: false,
          error: `Tool execution failed: ${error.message}`,
          details: {
            tool: tool.name,
            errorCode: error.code,
            suggestion: error.message.includes('Syntax error') 
              ? 'Shell parsing error with prompt. Using file-based approach for future calls.'
              : 'Command execution failed. Please check the tool configuration and try again.'
          }
        };
        
        mcpLog(`Returning error response instead of throwing: ${JSON.stringify(errorResponse)}`);
        return JSON.stringify(errorResponse);
      }
  }

  async start() {
          mcpLog("Starting local MCP server...", 'startup');
    
    // Load initial tool definitions
    this.loadToolDefinitions();
    
    // Create stdio transport
    const transport = new StdioServerTransport();
    
    // Connect the server
    await this.server.connect(transport);
    
          mcpLog(`🚀 MCP Server ready - ${this.tools.length} tools available`, 'startup');
  }
}

// Start the server
async function main() {
  try {
    const server = new LocalMCPServer();
    await server.start();
  } catch (error) {
    mcpLog(`Failed to start server: ${error.message}`, 'error');
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on("SIGTERM", () => {
  mcpLog("Received SIGTERM, shutting down gracefully");
  process.exit(0);
});

process.on("SIGINT", () => {
  mcpLog("Received SIGINT, shutting down gracefully");
  process.exit(0);
});

// Start the server if this file is run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
} 
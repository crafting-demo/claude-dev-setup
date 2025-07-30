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

// Enhanced logging that writes to both console and file
const LOG_FILE = path.join(os.homedir(), "cmd", "mcp-server-debug.log");
const SESSION_STATE_FILE = path.join(os.homedir(), "cmd", "session-state.json");

function mcpLog(message) {
  const timestamp = new Date().toISOString();
  const prefixedMessage = `[LOCAL-MCP] ${message}`;
  const logLine = `${timestamp} ${prefixedMessage}`;
  
  // Always log to console (for Claude Code)
  console.log(prefixedMessage);
  
  // Also log to file (for start-worker.sh tailing)
  try {
    appendFileSync(LOG_FILE, logLine + '\n');
  } catch (error) {
    // Silently fail if we can't write to log file
  }
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

  loadToolDefinitions() {
    const configPath = path.join(os.homedir(), "cmd", "local_mcp_tools.txt");
    
    mcpLog(`Looking for config at: ${configPath}`);
    
          if (!existsSync(configPath)) {
        mcpLog(`Config file not found: ${configPath}`);
        return;
      }

    try {
      const configContent = readFileSync(configPath, "utf-8");
      mcpLog(`Raw config content: ${configContent.substring(0, 200)}...`);
      
      // Handle both JSON format and simple text format
      let toolsConfig;
      try {
        toolsConfig = JSON.parse(configContent);
      } catch (parseError) {
        mcpLog(`JSON parse error: ${parseError.message}`);
        mcpLog("Using simple text format for tool definitions");
        return;
      }

      // The config should be an array directly, not wrapped in a "tools" property
      if (Array.isArray(toolsConfig)) {
        this.tools = toolsConfig;
        mcpLog(`Loaded ${this.tools.length} tool definitions from array format`);
        
        // Log tool names for debugging
        this.tools.forEach(tool => {
          mcpLog(`- ${tool.name}: ${tool.description || "No description"}`);
        });
      } else if (toolsConfig && toolsConfig.tools && Array.isArray(toolsConfig.tools)) {
        this.tools = toolsConfig.tools;
        mcpLog(`Loaded ${this.tools.length} tool definitions from wrapped format`);
        
        // Log tool names for debugging
        this.tools.forEach(tool => {
          mcpLog(`- ${tool.name}: ${tool.description || "No description"}`);
        });
              } else {
          mcpLog("Invalid tool configuration format");
          mcpLog(`Expected array or object with 'tools' property, got: ${typeof toolsConfig}`);
          if (toolsConfig) {
            mcpLog(`Config keys: ${Object.keys(toolsConfig)}`);
          }
        }
          } catch (error) {
        mcpLog(`Error loading tool definitions: ${error.message}`);
        mcpLog(`Stack trace: ${error.stack}`);
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
              },
              continue_session: {
                type: "boolean",
                description: "Whether to continue previous conversation context",
                default: false
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
      
      mcpLog(`=====================================`);
      mcpLog(`🔧 TOOL CALL INITIATED: ${name}`);
      mcpLog(`=====================================`);
      mcpLog(`Arguments:`, JSON.stringify(args, null, 2));
      mcpLog(`Available tools: ${this.tools.map(t => t.name).join(', ')}`);
      mcpLog(`Timestamp: ${new Date().toISOString()}`);
      
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
    mcpLog(`=====================================`);
    mcpLog(`executeTool called for: ${tool.name}`);
    mcpLog(`Tool configuration:`, JSON.stringify(tool, null, 2));
    mcpLog(`Arguments:`, JSON.stringify(args, null, 2));
    
    // Check for previous persistent session
    const previousSession = this.getToolSession(tool.name);
    const continueSession = args.continue_session || false;
    
    // Build the Claude command based on tool configuration
    let claudeCommand;
    let usingPreviousSession = false;
    
    mcpLog(`Continue session: ${continueSession}`);
    mcpLog(`Previous persistent session: ${previousSession ? previousSession.sessionId : 'none'}`);
    
    if (tool.prompt) {
      // Use the configured prompt template with dynamic parameter replacement
      let prompt = tool.prompt;
      
      // Handle double-brace templating: {{parameter_name}}
      mcpLog(`Processing template parameters...`);
      mcpLog(`Available args:`, JSON.stringify(args, null, 2));
      
             // Replace {{parameter}} with values from args
       prompt = prompt.replace(/\{\{([^}]+)\}\}/g, (match, paramName) => {
         const paramValue = args[paramName];
         if (paramValue !== undefined) {
           mcpLog(`Replacing {{${paramName}}} with: ${paramValue.substring(0, 100)}...`);
           return paramValue;
         } else {
           mcpLog(`Warning: Parameter {{${paramName}}} not found in args, leaving as-is`);
           return match; // Leave the placeholder if parameter not found
         }
       });
      
      mcpLog(`Using configured prompt template`);
      mcpLog(`Original template: ${tool.prompt.substring(0, 200)}...`);
      mcpLog(`Final prompt: ${prompt.substring(0, 200)}...`);
      
      // Check if we should use previous persistent session or continue with in-memory session
      if (previousSession && previousSession.sessionId) {
        // Change to the directory where the previous session was created
        const originalCwd = process.cwd();
        if (previousSession.workingDirectory !== originalCwd) {
          mcpLog(`Changing directory from ${originalCwd} to ${previousSession.workingDirectory} for session resume`);
          process.chdir(previousSession.workingDirectory);
        }
        
        claudeCommand = `claude --resume ${previousSession.sessionId} -p "${prompt.replace(/"/g, '\\"')}"`;
        usingPreviousSession = true;
        mcpLog(`Resuming persistent session ${previousSession.sessionId} for tool: ${tool.name}`);
      } else if (continueSession && this.sessions.has(tool.name)) {
        // Continue previous session (legacy behavior)
        claudeCommand = `claude -c -p "${prompt.replace(/"/g, '\\"')}"`;
        mcpLog(`Continuing in-memory session for tool: ${tool.name}`);
      } else {
        // Start new session 
        claudeCommand = `claude -p "${prompt.replace(/"/g, '\\"')}"`;
        this.sessions.set(tool.name, Date.now());
        mcpLog(`Starting new session for tool: ${tool.name}`);
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
      
      // Check if we should use previous persistent session or continue with in-memory session
      if (previousSession && previousSession.sessionId) {
        // Change to the directory where the previous session was created
        const originalCwd = process.cwd();
        if (previousSession.workingDirectory !== originalCwd) {
          mcpLog(`Changing directory from ${originalCwd} to ${previousSession.workingDirectory} for session resume`);
          process.chdir(previousSession.workingDirectory);
        }
        
        claudeCommand = `claude --resume ${previousSession.sessionId} -p "${prompt.replace(/"/g, '\\"')}"`;
        usingPreviousSession = true;
        mcpLog(`Resuming persistent session ${previousSession.sessionId} for tool: ${tool.name}`);
      } else if (continueSession && this.sessions.has(tool.name)) {
        claudeCommand = `claude -c -p "${prompt.replace(/"/g, '\\"')}"`;
        mcpLog(`Continuing in-memory session for tool: ${tool.name}`);
      } else {
        claudeCommand = `claude -p "${prompt.replace(/"/g, '\\"')}"`;
        this.sessions.set(tool.name, Date.now());
        mcpLog(`Starting new session for tool: ${tool.name}`);
      }
    }

    mcpLog(`Final Claude command: ${claudeCommand}`);
    
    try {
      // Execute the Claude command
      mcpLog(`Executing Claude command...`);
      const result = execSync(claudeCommand, {
        encoding: "utf-8",
        timeout: 900000, // 15 minute timeout (increased from 5 minutes)
        maxBuffer: 1024 * 1024 * 10 // 10MB buffer
      });
      
      // Save the session after successful execution (only if we're not using a previous session)
      if (!usingPreviousSession) {
        mcpLog(`Saving new session for tool: ${tool.name}`);
        this.saveToolSession(tool.name);
      } else {
        mcpLog(`Updated existing session for tool: ${tool.name}`);
        // Update the lastUsed timestamp for the existing session
        const sessionState = this.getSessionState();
        if (sessionState[tool.name]) {
          sessionState[tool.name].lastUsed = new Date().toISOString();
          this.saveSessionState(sessionState);
        }
      }
      
      mcpLog(`=====================================`);
      mcpLog(`✅ TOOL CALL COMPLETED: ${tool.name}`);
      mcpLog(`=====================================`);
      mcpLog(`Raw result length: ${result.length} characters`);
      mcpLog(`Result preview: ${result.substring(0, 300)}...`);
      mcpLog(`Completed at: ${new Date().toISOString()}`);
      return result.trim();
      
          } catch (error) {
        mcpLog(`Claude execution failed for tool ${tool.name}`);
        mcpLog(`Command: ${claudeCommand}`);
        mcpLog(`Error message: ${error.message}`);
        mcpLog(`Error code: ${error.code}`);
        mcpLog(`Error signal: ${error.signal}`);
        
        // Clean up session if there was an error
        this.sessions.delete(tool.name);
        
        throw new Error(`Claude execution failed: ${error.message}`);
      }
  }

  async start() {
    mcpLog("Starting local MCP server...");
    
    // Load initial tool definitions
    this.loadToolDefinitions();
    
    // Create stdio transport
    const transport = new StdioServerTransport();
    
    // Connect the server
    await this.server.connect(transport);
    
    mcpLog("=====================================");
    mcpLog("🚀 LOCAL MCP SERVER READY");
    mcpLog("=====================================");
    mcpLog("Server started and listening on stdio");
    mcpLog(`Serving ${this.tools.length} tools`);
          if (this.tools.length > 0) {
        mcpLog("Available tools:");
        this.tools.forEach(tool => {
          mcpLog(`  - ${tool.name}: ${tool.description || "No description"}`);
        });
      }
    mcpLog("Waiting for tool calls...");
  }
}

// Start the server
async function main() {
  try {
    const server = new LocalMCPServer();
    await server.start();
  } catch (error) {
    mcpLog(`Failed to start server: ${error.message}`);
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
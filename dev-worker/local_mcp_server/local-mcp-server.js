#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, existsSync, appendFileSync } from "fs";
import { execSync } from "child_process";
import os from "os";
import path from "path";

// Enhanced logging that writes to both console and file
const LOG_FILE = path.join(os.homedir(), "cmd", "mcp-server-debug.log");

function mcpLog(message) {
  const timestamp = new Date().toISOString();
  const logLine = `${timestamp} ${message}`;
  
  // Always log to console (for Claude Code)
  console.log(message);
  
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

  loadToolDefinitions() {
    const configPath = path.join(os.homedir(), "cmd", "local_mcp_tools.txt");
    
    mcpLog(`[LOCAL-MCP] Looking for config at: ${configPath}`);
    
          if (!existsSync(configPath)) {
        mcpLog(`[LOCAL-MCP] Config file not found: ${configPath}`);
        return;
      }

    try {
      const configContent = readFileSync(configPath, "utf-8");
      mcpLog(`[LOCAL-MCP] Raw config content: ${configContent.substring(0, 200)}...`);
      
      // Handle both JSON format and simple text format
      let toolsConfig;
      try {
        toolsConfig = JSON.parse(configContent);
      } catch (parseError) {
        mcpLog(`[LOCAL-MCP] JSON parse error: ${parseError.message}`);
        mcpLog("[LOCAL-MCP] Using simple text format for tool definitions");
        return;
      }

      // The config should be an array directly, not wrapped in a "tools" property
      if (Array.isArray(toolsConfig)) {
        this.tools = toolsConfig;
        mcpLog(`[LOCAL-MCP] Loaded ${this.tools.length} tool definitions from array format`);
        
        // Log tool names for debugging
        this.tools.forEach(tool => {
          mcpLog(`[LOCAL-MCP] - ${tool.name}: ${tool.description || "No description"}`);
        });
      } else if (toolsConfig && toolsConfig.tools && Array.isArray(toolsConfig.tools)) {
        this.tools = toolsConfig.tools;
        mcpLog(`[LOCAL-MCP] Loaded ${this.tools.length} tool definitions from wrapped format`);
        
        // Log tool names for debugging
        this.tools.forEach(tool => {
          mcpLog(`[LOCAL-MCP] - ${tool.name}: ${tool.description || "No description"}`);
        });
              } else {
          mcpLog("[LOCAL-MCP] Invalid tool configuration format");
          mcpLog(`[LOCAL-MCP] Expected array or object with 'tools' property, got: ${typeof toolsConfig}`);
          if (toolsConfig) {
            mcpLog(`[LOCAL-MCP] Config keys: ${Object.keys(toolsConfig)}`);
          }
        }
          } catch (error) {
        mcpLog(`[LOCAL-MCP] Error loading tool definitions: ${error.message}`);
        mcpLog(`[LOCAL-MCP] Stack trace: ${error.stack}`);
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
      
      mcpLog(`[LOCAL-MCP] =====================================`);
      mcpLog(`[LOCAL-MCP] 🔧 TOOL CALL INITIATED: ${name}`);
      mcpLog(`[LOCAL-MCP] =====================================`);
      mcpLog(`[LOCAL-MCP] Arguments:`, JSON.stringify(args, null, 2));
      mcpLog(`[LOCAL-MCP] Available tools: ${this.tools.map(t => t.name).join(', ')}`);
      mcpLog(`[LOCAL-MCP] Timestamp: ${new Date().toISOString()}`);
      
      // Find the tool definition
      const tool = this.tools.find(t => t.name === name);
              if (!tool) {
          const error = `Tool not found: ${name}. Available tools: ${this.tools.map(t => t.name).join(', ')}`;
          mcpLog(`[LOCAL-MCP] ${error}`);
          throw new Error(error);
        }

      mcpLog(`[LOCAL-MCP] Found tool definition for: ${tool.name}`);
      mcpLog(`[LOCAL-MCP] Tool prompt: ${tool.prompt?.substring(0, 100)}...`);

      try {
        const result = await this.executeTool(tool, args);
        mcpLog(`[LOCAL-MCP] Tool execution completed successfully`);
        mcpLog(`[LOCAL-MCP] Result length: ${result.length} characters`);
        return {
          content: [
            {
              type: "text",
              text: result
            }
          ]
        };
              } catch (error) {
          mcpLog(`[LOCAL-MCP] Error executing tool ${name}: ${error.message}`);
          mcpLog(`[LOCAL-MCP] Error stack: ${error.stack}`);
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
    mcpLog(`[LOCAL-MCP] =====================================`);
    mcpLog(`[LOCAL-MCP] executeTool called for: ${tool.name}`);
    mcpLog(`[LOCAL-MCP] Tool configuration:`, JSON.stringify(tool, null, 2));
    mcpLog(`[LOCAL-MCP] Arguments:`, JSON.stringify(args, null, 2));
    
    // Build the Claude command based on tool configuration
    let claudeCommand;
    // Extract input from tool-specific parameters (e.g., question, input, etc.)
    const input = args.question || args.input || "";
    const continueSession = args.continue_session || false;
    
    mcpLog(`[LOCAL-MCP] Input: "${input}"`);
    mcpLog(`[LOCAL-MCP] Continue session: ${continueSession}`);
    
    if (tool.prompt) {
      // Use the configured prompt template
      const prompt = tool.prompt.replace(/\{input\}/g, input);
      mcpLog(`[LOCAL-MCP] Using configured prompt template`);
      mcpLog(`[LOCAL-MCP] Prompt template: ${tool.prompt.substring(0, 200)}...`);
      
      if (continueSession && this.sessions.has(tool.name)) {
        // Continue previous session
        claudeCommand = `claude -c -p "${prompt.replace(/"/g, '\\"')}"`;
        mcpLog(`[LOCAL-MCP] Continuing session for tool: ${tool.name}`);
      } else {
        // Start new session 
        claudeCommand = `claude -p "${prompt.replace(/"/g, '\\"')}"`;
        this.sessions.set(tool.name, Date.now());
        mcpLog(`[LOCAL-MCP] Starting new session for tool: ${tool.name}`);
      }
    } else {
      // Default behavior: pass input directly to Claude
      const prompt = `Execute this task: ${input}`;
      mcpLog(`[LOCAL-MCP] Using default prompt behavior`);
      
      if (continueSession && this.sessions.has(tool.name)) {
        claudeCommand = `claude -c -p "${prompt.replace(/"/g, '\\"')}"`;
      } else {
        claudeCommand = `claude -p "${prompt.replace(/"/g, '\\"')}"`;
        this.sessions.set(tool.name, Date.now());
      }
    }

    mcpLog(`[LOCAL-MCP] Final Claude command: ${claudeCommand}`);
    
    try {
      // Execute the Claude command
      mcpLog(`[LOCAL-MCP] Executing Claude command...`);
      const result = execSync(claudeCommand, {
        encoding: "utf-8",
        timeout: 900000, // 15 minute timeout (increased from 5 minutes)
        maxBuffer: 1024 * 1024 * 10 // 10MB buffer
      });
      
      mcpLog(`[LOCAL-MCP] =====================================`);
      mcpLog(`[LOCAL-MCP] ✅ TOOL CALL COMPLETED: ${tool.name}`);
      mcpLog(`[LOCAL-MCP] =====================================`);
      mcpLog(`[LOCAL-MCP] Raw result length: ${result.length} characters`);
      mcpLog(`[LOCAL-MCP] Result preview: ${result.substring(0, 300)}...`);
      mcpLog(`[LOCAL-MCP] Completed at: ${new Date().toISOString()}`);
      return result.trim();
      
          } catch (error) {
        mcpLog(`[LOCAL-MCP] Claude execution failed for tool ${tool.name}`);
        mcpLog(`[LOCAL-MCP] Command: ${claudeCommand}`);
        mcpLog(`[LOCAL-MCP] Error message: ${error.message}`);
        mcpLog(`[LOCAL-MCP] Error code: ${error.code}`);
        mcpLog(`[LOCAL-MCP] Error signal: ${error.signal}`);
        
        // Clean up session if there was an error
        this.sessions.delete(tool.name);
        
        throw new Error(`Claude execution failed: ${error.message}`);
      }
  }

  async start() {
    mcpLog("[LOCAL-MCP] Starting local MCP server...");
    
    // Load initial tool definitions
    this.loadToolDefinitions();
    
    // Create stdio transport
    const transport = new StdioServerTransport();
    
    // Connect the server
    await this.server.connect(transport);
    
    mcpLog("[LOCAL-MCP] =====================================");
    mcpLog("[LOCAL-MCP] 🚀 LOCAL MCP SERVER READY");
    mcpLog("[LOCAL-MCP] =====================================");
    mcpLog("[LOCAL-MCP] Server started and listening on stdio");
    mcpLog(`[LOCAL-MCP] Serving ${this.tools.length} tools`);
          if (this.tools.length > 0) {
        mcpLog("[LOCAL-MCP] Available tools:");
        this.tools.forEach(tool => {
          mcpLog(`[LOCAL-MCP]   - ${tool.name}: ${tool.description || "No description"}`);
        });
      }
    mcpLog("[LOCAL-MCP] Waiting for tool calls...");
  }
}

// Start the server
async function main() {
  try {
    const server = new LocalMCPServer();
    await server.start();
  } catch (error) {
    mcpLog(`[LOCAL-MCP] Failed to start server: ${error.message}`);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on("SIGTERM", () => {
  mcpLog("[LOCAL-MCP] Received SIGTERM, shutting down gracefully");
  process.exit(0);
});

process.on("SIGINT", () => {
  mcpLog("[LOCAL-MCP] Received SIGINT, shutting down gracefully");
  process.exit(0);
});

// Start the server if this file is run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
} 
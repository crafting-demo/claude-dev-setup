#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, existsSync } from "fs";
import { execSync } from "child_process";
import os from "os";
import path from "path";

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
    
    if (!existsSync(configPath)) {
      console.error(`[LOCAL-MCP] Config file not found: ${configPath}`);
      return;
    }

    try {
      const configContent = readFileSync(configPath, "utf-8");
      
      // Handle both JSON format and simple text format
      let toolsConfig;
      try {
        toolsConfig = JSON.parse(configContent);
      } catch (parseError) {
        // If not JSON, treat as simple text format (one tool per line)
        console.log("[LOCAL-MCP] Using simple text format for tool definitions");
        return;
      }

      if (toolsConfig && toolsConfig.tools && Array.isArray(toolsConfig.tools)) {
        this.tools = toolsConfig.tools;
        console.log(`[LOCAL-MCP] Loaded ${this.tools.length} tool definitions`);
        
        // Log tool names for debugging
        this.tools.forEach(tool => {
          console.log(`[LOCAL-MCP] - ${tool.name}: ${tool.description || "No description"}`);
        });
      } else {
        console.error("[LOCAL-MCP] Invalid tool configuration format");
      }
    } catch (error) {
      console.error(`[LOCAL-MCP] Error loading tool definitions: ${error.message}`);
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
      
      console.log(`[LOCAL-MCP] Executing tool: ${name}`);
      console.log(`[LOCAL-MCP] Arguments:`, args);
      
      // Find the tool definition
      const tool = this.tools.find(t => t.name === name);
      if (!tool) {
        throw new Error(`Tool not found: ${name}`);
      }

      try {
        const result = await this.executeTool(tool, args);
        return {
          content: [
            {
              type: "text",
              text: result
            }
          ]
        };
      } catch (error) {
        console.error(`[LOCAL-MCP] Error executing tool ${name}:`, error.message);
        return {
          content: [
            {
              type: "text", 
              text: `Error executing tool: ${error.message}`
            }
          ],
          isError: true
        };
      }
    });
  }

  async executeTool(tool, args) {
    // Build the Claude command based on tool configuration
    let claudeCommand;
    const input = args.input || "";
    const continueSession = args.continue_session || false;
    
    if (tool.prompt) {
      // Use the configured prompt template
      const prompt = tool.prompt.replace(/\{input\}/g, input);
      
      if (continueSession && this.sessions.has(tool.name)) {
        // Continue previous session
        claudeCommand = `claude -c -p "${prompt.replace(/"/g, '\\"')}"`;
        console.log(`[LOCAL-MCP] Continuing session for tool: ${tool.name}`);
      } else {
        // Start new session 
        claudeCommand = `claude -p "${prompt.replace(/"/g, '\\"')}"`;
        this.sessions.set(tool.name, Date.now());
        console.log(`[LOCAL-MCP] Starting new session for tool: ${tool.name}`);
      }
    } else {
      // Default behavior: pass input directly to Claude
      const prompt = `Execute this task: ${input}`;
      
      if (continueSession && this.sessions.has(tool.name)) {
        claudeCommand = `claude -c -p "${prompt.replace(/"/g, '\\"')}"`;
      } else {
        claudeCommand = `claude -p "${prompt.replace(/"/g, '\\"')}"`;
        this.sessions.set(tool.name, Date.now());
      }
    }

    console.log(`[LOCAL-MCP] Executing: ${claudeCommand}`);
    
    try {
      // Execute the Claude command
      const result = execSync(claudeCommand, {
        encoding: "utf-8",
        timeout: 300000, // 5 minute timeout
        maxBuffer: 1024 * 1024 * 10 // 10MB buffer
      });
      
      console.log(`[LOCAL-MCP] Tool ${tool.name} completed successfully`);
      return result.trim();
      
    } catch (error) {
      console.error(`[LOCAL-MCP] Claude execution failed:`, error.message);
      
      // Clean up session if there was an error
      this.sessions.delete(tool.name);
      
      if (error.killed) {
        throw new Error("Tool execution timed out");
      } else if (error.status) {
        throw new Error(`Claude exited with code ${error.status}: ${error.stderr || error.message}`);
      } else {
        throw new Error(`Execution failed: ${error.message}`);
      }
    }
  }

  async start() {
    console.log("[LOCAL-MCP] Starting local MCP server...");
    
    // Load initial tool definitions
    this.loadToolDefinitions();
    
    // Create stdio transport
    const transport = new StdioServerTransport();
    
    // Connect the server
    await this.server.connect(transport);
    
    console.log("[LOCAL-MCP] Server started and listening on stdio");
    console.log(`[LOCAL-MCP] Serving ${this.tools.length} tools`);
  }
}

// Start the server
async function main() {
  try {
    const server = new LocalMCPServer();
    await server.start();
  } catch (error) {
    console.error("[LOCAL-MCP] Failed to start server:", error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on("SIGTERM", () => {
  console.log("[LOCAL-MCP] Received SIGTERM, shutting down gracefully");
  process.exit(0);
});

process.on("SIGINT", () => {
  console.log("[LOCAL-MCP] Received SIGINT, shutting down gracefully");
  process.exit(0);
});

// Start the server if this file is run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
} 
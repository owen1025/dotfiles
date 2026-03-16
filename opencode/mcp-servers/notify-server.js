#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const NTFY_SERVER = process.env.NTFY_SERVER || "https://ntfy.sh";
const NTFY_TOPIC = process.env.NTFY_TOPIC || "gowid-opencode-notify";
const NTFY_TOKEN = process.env.NTFY_TOKEN;
const NTFY_USERNAME = process.env.NTFY_USERNAME;
const NTFY_PASSWORD = process.env.NTFY_PASSWORD;

const server = new Server(
  {
    name: "notify-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "send_notification",
        description: "Send a push notification to the user's phone via ntfy.sh. Use this when a significant task is completed, when user attention is needed, or when a long-running operation finishes.",
        inputSchema: {
          type: "object",
          properties: {
            message: {
              type: "string",
              description: "The notification message content",
            },
            title: {
              type: "string",
              description: "The notification title (optional, defaults to 'OpenCode')",
            },
            priority: {
              type: "string",
              enum: ["min", "low", "default", "high", "urgent"],
              description: "Notification priority (optional, defaults to 'default')",
            },
            tags: {
              type: "string",
              description: "Comma-separated emoji tags (optional, e.g., 'white_check_mark,tada')",
            },
            topic: {
              type: "string",
              description: "Notification topic override (optional, defaults to NTFY_TOPIC env var)",
            },
            server: {
              type: "string",
              description: "ntfy server URL override (optional, defaults to NTFY_SERVER env var or https://ntfy.sh)",
            },
          },
          required: ["message"],
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "send_notification") {
    const {
      message,
      title = "OpenCode",
      priority = "default",
      tags,
      topic,
      server,
    } = args;

    try {
      const resolvedTopic = topic || NTFY_TOPIC;
      const resolvedServer = (server || NTFY_SERVER).replace(/\/$/, "");

      if (!resolvedTopic) {
        throw new Error("Missing topic. Set NTFY_TOPIC or pass topic argument.");
      }

      const headers = {
        "Title": title,
        "Priority": priority,
        "Content-Type": "text/plain; charset=utf-8",
      };

      if (NTFY_TOKEN) {
        headers["Authorization"] = `Bearer ${NTFY_TOKEN}`;
      } else if (NTFY_USERNAME && NTFY_PASSWORD) {
        const basic = Buffer.from(`${NTFY_USERNAME}:${NTFY_PASSWORD}`).toString("base64");
        headers["Authorization"] = `Basic ${basic}`;
      }

      if (tags) {
        headers["Tags"] = tags;
      }

      const response = await fetch(`${resolvedServer}/${encodeURIComponent(resolvedTopic)}`, {
        method: "POST",
        headers,
        body: message,
      });

      if (response.ok) {
        return {
          content: [
            {
              type: "text",
              text: `Notification sent to ${resolvedServer}/${resolvedTopic}: "${message}"`,
            },
          ],
        };
      } else {
        const body = await response.text();
        throw new Error(`HTTP ${response.status}: ${response.statusText}${body ? ` - ${body}` : ""}`);
      }
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Failed to send notification: ${error.message}`,
          },
        ],
        isError: true,
      };
    }
  }

  return {
    content: [
      {
        type: "text",
        text: `Unknown tool: ${name}`,
      },
    ],
    isError: true,
  };
});

const transport = new StdioServerTransport();
await server.connect(transport);

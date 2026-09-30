// User-level stopgap: pi-web sessions run via the pi SDK, which does not load
// built-in extensions. This registers the built-in MCP integration so that
// servers from ~/.pi/agent/mcp.json connect in pi-web sessions.
// codemode + tool_search make every exposure mode reachable (codemode,
// codemode-deferred, deferred); direct works with the MCP extension alone.
// Remove this file once pi-web registers these extensions itself.
import {
  createMcpExtension,
  createCodemodeExtension,
  createToolSearchExtension,
} from "/usr/lib/node_modules/@earendil-works/pi-coding-agent/dist/index.js";

export default (pi) => {
  createMcpExtension()(pi);
  createCodemodeExtension()(pi);
  createToolSearchExtension()(pi);
};

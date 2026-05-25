# Watcher Examples

This directory is for project-specific watcher scripts.

Keep watchers outside the ORBIT core when they know about experiment schemas,
GPU policies, paper constraints, or domain-specific stop conditions. A watcher
should write durable JSONL notices through:

```bash
orbit notify researcher --from watcher --type watcher_event --severity stage "message"
```

The reusable core only defines the communication and notification protocol.

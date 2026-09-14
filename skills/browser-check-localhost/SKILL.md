---
name: browser-check-localhost
description: Check generated HTML pages (reports, documentation, static output) in the Claude Browser pane by serving them on 127.0.0.1 with a temporary .claude/launch.json http.server entry, because the pane refuses file:// URLs. Use when a change must be verified in a real browser.
---

# Browser check through localhost

The Browser pane does not open `file://` URLs. Do not try again with a
different navigate call. Serve the pages on localhost.

## Steps

1. **Make the pages.** Generate them into a git-ignored output directory or
   the scratchpad directory. Use example or synthetic inputs, not sensitive
   real data.
2. **Add a server entry.** If `.claude/launch.json` exists, it belongs to the
   user: add only your entry, and later remove only your entry. If it does
   not exist, create it:

   ```json
   {
     "version": "0.0.1",
     "configurations": [
       {
         "name": "page-check",
         "runtimeExecutable": "python3",
         "runtimeArgs": ["-m", "http.server", "8765", "--bind", "127.0.0.1", "--directory", "<absolute pages directory>"],
         "port": 8765
       }
     ]
   }
   ```

3. **Start and open.** `preview_start` with the name `page-check`, then
   navigate to `http://127.0.0.1:8765/<page>.html`.
4. **Verify.** Use `read_page`, `find`, or `javascript_tool` to check the
   state (for example `aria-pressed` values, hidden rows, and control
   results). Use `read_console_messages` with `onlyErrors`. Use screenshots
   only for layout.
5. **Remove everything.** `preview_stop`. Delete `.claude/launch.json` if you
   created it, or remove only your entry. Do not commit it. Delete the pages
   that you copied or generated for the check.

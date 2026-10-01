# Interrupted tool-sandbox preliminary run

The first command was:

```sh
/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 native/scripts/run_qa.py --configuration Release --storage-only --timeout 180
```

It ran under the Codex tool filesystem/process sandbox. Its raw logs are retained in `interrupted-sandbox-preliminary/`, copied from `native/build/qa/runs/20261001T224303089948Z/`.

This run was interrupted before completion, so it has no completed runner receipt and must not be counted as a valid full or partial passing QA run. The exact isolated QA runner and its own `ApplicationLifecycleTests` child were stopped to start the complete, authorized native regression. The installed DaBin app was not stopped or operated.

The preliminary environment caused readable archive documents, drag representations and backup checks to fail or stall. An unchanged complete native run was then started outside that tool sandbox, using the same test-module cache and source inputs. The initially failing archive, backup, transfer, workspace and lifecycle suites all passed there. The preliminary failures therefore cannot be presented as established product defects without reproduction in the native run.

Tests use fictional fixtures, unique temporary archives and private pasteboards. They do not operate the installed DaBin app, personal archive, real clipboard, permission prompts, actual notifications, external services or accounts.

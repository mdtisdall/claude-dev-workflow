---
name: parallel-agents
description: Split a task's implementation across concurrent sub-agents safely - each sub-agent owns different files, prompts are self-contained with no git writes, a model tier for each sub-task, the main agent reviews every diff, and refactors are compared byte-for-byte against a baseline worktree. Use when a plan phase or task is large enough to give to several Agent calls.
---

# Parallel sub-agents

There are two levels of parallel work:

- **Between tasks:** each task has its own branch and worktree (see the
  `start-task` skill), and usually its own Claude session. Two tasks never
  share a working tree.
- **In one task:** several sub-agents work in the task's worktree. Each
  sub-agent owns different files.

## Plan the split

- For each sub-agent, list every file that it will create or change. Two
  sub-agents that run at the same time must not share a file. This includes
  test files, `__init__` files, fixtures, lockfiles, and documentation. If two
  sub-agents need the same file, give the file to one of them, or run them one
  after the other. Tell the user about the change.
- Only the main agent syncs, locks, or installs dependencies, one time, before
  the sub-agents start.
- If the plan has a gap (a file that no sub-agent owns, or a decision that is
  not made), resolve it with the user before you start the sub-agents.

## Model tier

| Tier | Model | Work |
|---|---|---|
| T1 | `haiku` | Mechanical work: renames, code moves, fixture regeneration, doc edits with the exact text given |
| T2 | `sonnet` | Usual feature or fix work, with a clear specification and tests |
| T3 | `opus` | Design decisions, subtle correctness, refactors across modules |

If you are not sure, use the next higher tier.

## Sub-agent prompt

A sub-agent cannot see this conversation, so the prompt must contain all the
information:

```
Goal: <one paragraph>
Worktree: <absolute path>. Use absolute paths. Do not work outside the worktree.
You own these files, and you may create or change only these: <files>
Read-only context: <files, documents, decisions already made>
Constraints:
- Do not run git commands that write (add, commit, push, checkout, switch,
  stash, reset, rebase, merge, worktree).
- Do not sync, lock, or install dependencies.
- If the behavior changes, write or change the tests first. Run only the tests
  for your files: <command>.
- Do not write facts that you did not verify in docstrings or comments. If you
  do not know, leave it out and tell me in your report.
Report: the files that you changed, the tests that you ran and their results,
and each item that is uncertain or not done.
```

Start the sub-agents of one group in one message, so that they run at the same
time.

## Review each diff (main agent)

Read each sub-agent's diff yourself (`git -C <wt> diff`) before you run the
checks. Sub-agents write code that looks correct but is not. Examples seen in
real work: a value read eagerly that had to be read lazily, a CLI flag
interpreted as a path, and a docstring that described behavior the code does
not have. Then run all the project checks. A sub-agent's report is a claim,
not evidence.

## Refactors that must not change behavior

1. **Baseline:** like every worktree, it goes in `.worktrees/` of the main
   checkout:
   `git -C <main checkout> worktree add --detach .worktrees/base origin/<default>`.
   You can use the same baseline for several refactor tasks. To refresh it
   after a fetch:
   `git -C <main checkout>/.worktrees/base checkout --detach origin/<default>`.
   Sync its dependencies one time.
2. Run the same commands, with the same inputs, in the baseline and in the
   task worktree. Write the outputs to two different directories.
3. Compare the outputs byte-for-byte (`diff -r`, `cmp`). Explain or correct
   each difference.
4. If the inputs are sensitive (real data, patient data, credentials), report
   only counts, file names, and column names. Do not report values.
5. When no more refactors need the baseline, remove it:
   `git -C <main checkout> worktree remove .worktrees/base`.

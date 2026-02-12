# Git Cleanup Plan for AppViewModel.swift

## Methods to Remove (vestigial git operations):
1. `isGitRepo` (line 243)
2. `setControlRepo` (line 962) 
3. `checkControlRepoStatus` (line 1119)
4. `checkRebaseState` (line 1726)
5. `gitDirURL` (line 1857)
6. `loadCurrentConflictFiles` (line 2048)
7. `syncGitHubCache` (line 1410) - replace with API call
8. `pushNow` (line 1459) - not needed in API mode
9. `syncRepo/syncRepoAsync` (line 4270, 4275)
10. `autoCommitLocalChanges/autoCommitLocalChangesAsync` (line 4280, 4285)
11. `commitAndMaybePush/asyncCommitAndMaybePush` (line 4246, 4289)

## Properties to Remove:
1. `repoPath` - published property (line 32)
2. `repoURL` - computed property (around line 950)
3. `controlRepoAhead/controlRepoBehind` - if exists

## Methods to Keep:
1. `createGitHubIssue` - uses GitHub API via GitHubService
2. `updateProjectSyncMode` - just updates project config

## Replacements Needed:
1. `syncGitHubCache()` → use `api.syncGitHubProject(projectId:)` which already exists
2. Remove all calls to git operations from `reload()` and other methods

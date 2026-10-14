# Maintaining

## Publish a new version

From a clean working tree on `main`, with the GitHub CLI authenticated, run:

```sh
./release 0.0.1
```

This updates `CFBundleShortVersionString` in `source/Info.plist`, commits and pushes the version bump, and starts the Release workflow. The workflow tests, pushes the `v0.0.1` tag, and creates the GitHub release with the compiled library, `SOML.scptd.zip`.

If starting the workflow fails after the push, retry with `gh workflow run release.yml --ref main`.

If the workflow fails after it pushes the tag, delete the tag before you run it again: `git push origin :refs/tags/v1.2.3`

<!--
This is an upstream GitLab merge-request template and does NOT apply to the piclas-win
Windows fork, which is developed on GitHub. Contribute via a GitHub Pull Request against
`master` of https://github.com/HallGrossaxt/piclas-windows (CI runs as the GitHub Actions
build workflows in .github/workflows/).

The upstream PICLas feature-MR checklist (GitLab pipelines, DO_CHECKIN, warning/file-size
tools, REGGIE table, AppImage test pipeline) lives upstream:
  https://piclas.readthedocs.io/en/latest/developerguide/git_workflow.html
-->

## Windows-port Pull Request checklist

* [ ] Builds with the Windows CMake presets (`windows-ucrt64-mpi`, …)
* [ ] Relevant reggie regression checks pass with `piclas-win.exe` (see README)
* [ ] GPLv3 attribution / "unofficial Windows port" notices left intact
* [ ] Linux behaviour unchanged (Windows changes guarded by `_WIN32` / `WIN32`)

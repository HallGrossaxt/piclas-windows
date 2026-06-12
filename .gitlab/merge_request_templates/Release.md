<!--
This is an upstream GitLab release merge-request template and does NOT apply to the
piclas-win Windows fork, which is developed and released on GitHub. The upstream PICLas
release procedure (updatePiclasVersion.sh, boltzplatz pipelines, AppImage build/test,
GitHub mirror push, GitLab tags/releases) lives upstream:
  https://piclas.readthedocs.io/en/latest/developerguide/git_workflow.html

For the Windows fork, cut releases from `master` of
https://github.com/HallGrossaxt/piclas-windows using GitHub Releases. The executable name
is `piclas-win.exe`; the piclas-win version string is set in src/piclaslib.f90.
-->

## Windows-port release checklist

* [ ] Bump the `piclas-win` version string (src banner) and any docs that cite it
* [ ] Green GitHub Actions build workflows (DSMC+GPU+MPI, piclas2vtk, SuperB)
* [ ] Key reggie regression suites pass with the release binary
* [ ] Draft a GitHub Release with notes summarising the changes since the last tag

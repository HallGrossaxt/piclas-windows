# Git Workflow (Windows port)

> **piclas-win** is developed on **GitHub** at
> [HallGrossaxt/piclas-windows](https://github.com/HallGrossaxt/piclas-windows). Contributions use
> feature branches and **Pull Requests** against `master`. Continuous integration runs as the
> GitHub Actions build workflows in `.github/workflows/` — not the upstream GitLab pipelines.
>
> The upstream PICLas project uses a GitLab-based workflow (issues, milestones, merge requests,
> protected `master`/`master.dev`, nightly/weekly regression pipelines, release & deploy procedure).
> For that process, see the upstream original:
> <https://piclas.readthedocs.io/en/latest/developerguide/git_workflow.html>

## Contributing to the Windows port

1. Branch off `master` and make your change on a feature branch.
2. Build with the Windows CMake presets and run the relevant reggie regression checks
   (see the [README](../../../README.md)).
3. Open a Pull Request against `master` of this repository.

Keep the GPLv3 modification/attribution notices ("unofficial Windows port, based on …") intact.

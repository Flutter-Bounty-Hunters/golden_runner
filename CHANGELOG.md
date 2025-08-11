## 0.2.0
### Aug 11, 2025
 * A Dockerfile is no longer required - a default Dockerfile is sent to Docker by this package.
 * Docker verbosity is configurable - you can now stop most/all Docker output to terminal.
 * `flutter test` output now displays in color, and also updates itself via interactive terminal, instead of printing many lines per test run.

## 0.1.0
Initial Release:
 * CLI app called `goldens`.
   * Test goldens with `goldens test`.
   * Update updates with `goldens update`.
   * Uses a Docker container to run goldens as Ubuntu.
 

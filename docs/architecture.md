# Architecture

## Design Goals

- Local-first monitoring and enforcement
- Minimal resource usage
- Cross-platform operability from one repository
- Configurable strictness and alert style

## Components

1. Runtime Engine
- Platform-specific monitor loop.
- Detects context (foreground app/tab/package + idle state).
- Applies policy decision.

2. Policy Layer
- Stream/distraction domain or package patterns.
- Away-from-system threshold.
- Streak thresholds to prevent immediate false-positive closures.

3. Enforcement Layer
- Close tab/window/home-screen action.
- Alert sound and optional visual cue.

4. Scheduler Layer
- macOS: launchd agent.
- Windows: Task Scheduler startup task.
- Android: ADB-driven monitor loop from host machine.

## Performance Strategy

- Cache decisions across loops.
- Run expensive checks at larger intervals.
- Disable persistence by default.
- Keep model parameters conservative.

## Security and Privacy

- No cloud calls in default workflows.
- No telemetry pipeline.
- Local files only, user-controlled retention.

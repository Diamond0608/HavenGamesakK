# Haven Games — script layout

## Current runtime flow

- `world.gd` is the scene-level coordinator. It finds the plane and passes each physics frame to the movement module.
- `scripts/plane/plane_movement.gd` owns plane movement, boundary detection, bounce response, and speed growth.
- `scripts/world/world_bounds.gd` owns bounds validation and position clamping.
- `scripts/destinations/destination.gd` owns click detection and emits `destination_clicked`.

The existing airport and carrier script paths remain as thin compatibility wrappers. Their current scene attachments therefore do not need to be changed just to share the destination implementation.

## Boundary behavior

The bounds are a `Rect2(position, size)`, not two corner coordinates. The current values describe:

- Top-left: `(-808, -488)`
- Size: `(1381, 890)`
- Bottom-right: `(573, 402)`

Movement is advanced using the time remaining in the current physics frame. If a fast plane crosses an edge, the module places it at the edge, reverses its direction by 180 degrees, doubles its speed, and simulates the remaining frame time at the new speed. This prevents repeated boundary detection from doubling speed every frame while the plane is stuck on an edge.

`max_speed` in the World Inspector defaults to `20000`. It prevents exponential speed growth from eventually overflowing to infinity. Increase it in the Inspector if you deliberately want a higher cap.

A maximum of 64 bounces is processed in one physics frame as a safety limit.

## Adding features independently

- Plane selection/clicking: add a separate script under `scripts/plane/`. It should emit a selection signal rather than changing movement variables directly.
- Landing: add a separate landing controller under `scripts/plane/`. It can listen for destination selection and own landing state/animation.
- Destinations: connect each Area2D's inherited `destination_clicked` signal to the world-level destination/route coordinator.

Keep these features separate from `plane_movement.gd`; that module should remain responsible only for movement and boundary physics.

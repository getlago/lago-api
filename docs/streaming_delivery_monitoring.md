# Monitoring streaming deliveries

The delivery path has no persisted record of a delivery and no retry. A snapshot that fails to
reach the stream is gone, superseded by the next wallet refresh. That makes its log lines the
only observable, and it makes silence indistinguishable from health unless something watches for
it.

This is not hypothetical. The inbound Kinesis connector once ran for 14 days with no production
events reaching Lago, because a Pulumi import overwrote the shared IAM role's trust policy.
Nothing alerted. The egress direction has the same failure class: the credentials stop working,
every delivery fails the same way, and no customer complains until they notice their usage is
stale.

## The log contract

Every delivery emits exactly one line, from `EventDestinations::DeliveryLogger`. The keys are a
contract. Renaming one does not fail a build, it silently unhooks the monitors below.

```
[streaming] event=delivery outcome=<outcome> destination_id=<uuid> organization_id=<uuid> ...
```

| `outcome`    | Severity | Meaning | Emitted by |
|--------------|----------|---------|------------|
| `delivered`  | info  | A record landed on the stream. Carries `shard`, `sequence`, `bytes`, `duration_ms`. | `KinesisProducer` |
| `throttled`  | error | The stream is out of shard capacity. The fix is a shard count from the stream's owner. | `KinesisProducer` |
| `dropped`    | error | Configuration or connectivity fault. The record is gone and no retry would recover it. Carries `error` and `message`. | `KinesisProducer` |
| `superseded` | info  | A newer delivery for this customer was already queued or running, so this one was abandoned. Expected under bursts. | `DeliverEventJob` |
| `skipped`    | warn  | Usage could not be computed for one subscription. | `RefreshedService` |
| `failed`     | error | Anything unexpected, isolated to one subscription. | `RefreshedService` |

Values are logfmt, so `outcome:delivered` and `destination_id:<uuid>` are directly facetable
once a Datadog parser is attached to the `[streaming] event=delivery` prefix.

## Monitors to create

These live in Datadog, not in this repository. All of them page.

1. **Delivery failures.** Count of `outcome:dropped` over 5 minutes, grouped by
   `destination_id`. Any sustained non-zero value is a fault: unlike a webhook, nothing retries.
   The `error` field says which of the failure modes below it is.

2. **Throttling.** Count of `outcome:throttled` over 5 minutes, grouped by `destination_id`.
   Separate from failures because the remediation is different and sits with whoever owns the
   stream: they have to add shards. See ING-653 for the sizing math.

3. **A destination gone quiet.** No `outcome:delivered` for a `destination_id` over an interval
   comfortably longer than that organization's refresh cadence. This is the INC-176 shape and
   the only monitor that fires when everything fails uniformly, since a destination whose
   credentials stopped working produces `dropped` lines, but one whose jobs stopped being
   enqueued at all produces nothing. Group by `destination_id`: with two Synthesia
   organizations live, one going quiet while the other stays healthy must still page.

4. **Drop rate.** Ratio of `outcome:superseded` to `outcome:delivered`. Not a fault on its own,
   since dropping an overlapping delivery is the design. A rising ratio means deliveries are
   taking longer than the interval between refreshes, which is the early warning that the
   worker is undersized before freshness starts slipping.

## Failure modes and what each one means

Every one of these is logged per subscription while the service still returns success, so none
of them surfaces as a failed job.

| `error` | What actually broke |
|---------|---------------------|
| `Aws::Kinesis::Errors::ResourceNotFoundException` | The stream ARN points at nothing. |
| `Aws::Kinesis::Errors::AccessDeniedException` | Usually the same thing. On a role scoped to a single stream, a typo'd ARN comes back as AccessDenied rather than NotFound. |
| `Aws::STS::Errors::AccessDenied` | The AssumeRole call failed: the trust policy is wrong or was overwritten. This is the INC-176 failure. |
| `Aws::Errors::MissingCredentialsError` | The worker resolved no base credentials at all, so there was nothing to assume the role from. |
| `Seahorse::Client::NetworkingError` | STS or the stream is unreachable. |
| `Aws::Kinesis::Errors::ValidationException` | The record exceeded the 1MB Kinesis cap. Measured payloads are 1417 to 1436 bytes, so this means something changed shape, not that usage grew. |

## What is deliberately not measured here

Job-level throughput, queue depth and latency for the `streaming` queue come from the existing
Sidekiq Pro metrics, which already reach Datadog via StatsD. Nothing in this document duplicates
them.

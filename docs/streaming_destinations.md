# Streaming destinations

A streaming destination is a row that says where an organization's events should be sent. If an
organization has no row, nothing is delivered and nothing is logged. That presence check is the
whole gate: there is no feature flag, no environment variable, and no API.

Today one event type exists, `customer_usage.refreshed`, produced on every wallet refresh, and
one destination type, Kinesis.

## Creating one

There is no rake task, no admin screen and no GraphQL for creating a destination. Nobody outside
one customer is asking for this yet, and a handful of rows a year is manageable by hand. That
decision only holds while the procedure is written down, which is what this document is for.

### Before you touch the console

Two things have to already exist, and infra owns both:

1. **The stream.** Whoever consumes the records provisions it and tells you the ARN and region.
2. **The writer role,** and a trust policy on it that lets the streaming worker's service
   account assume it. The application makes the AssumeRole call itself, so nothing works until
   this exists. This is the piece that broke on the ingest side and went unnoticed for 14 days,
   see `docs/streaming_delivery_monitoring.md`.

You also need to know **which organization** the stream belongs to. This is the step that goes
wrong. An organization's production and development environments are often two separate
organizations on the same database, and their stream ARNs differ only by an account id or a
suffix. Getting them crossed sends one environment's usage to the other's consumer, and nothing
in the system will tell you: both destinations look healthy and both emit `outcome=delivered`.

Read the account id in the ARN out loud against the environment you think you are configuring
before you create anything.

### The row

```ruby
organization = Organization.find("<organization uuid>")

StreamingDestinations::KinesisDestination.create!(
  organization:,
  event_types: ["customer_usage.refreshed"],
  settings: {
    stream_arn: "arn:aws:kinesis:eu-west-1:123456789012:stream/<stream name>",
    region: "eu-west-1",
    role_arn: "arn:aws:iam::123456789012:role/<writer role>",
    partition_key: "customer_external_id"
  }
)
```

| Setting | Required | Notes |
|---------|----------|-------|
| `stream_arn` | yes | The full ARN, not the stream name. Its account id is the thing to double-check. |
| `region` | yes | Used for both the Kinesis client and the STS client that assumes the role. |
| `role_arn` | yes | Infrastructure config, not a credential: holding it grants nothing unless the worker's identity is already allowed to assume it. That is why it is in `settings` and not `secrets`. |
| `partition_key` | no | How records are grouped onto shards. Only `customer_external_id` is implemented, which is also the default: it keeps one customer's records in order. |

`secrets` stays empty for Kinesis. The column exists for destination types that carry a real
credential, such as a Kafka SASL password.

`event_types` is validated against the known list, so a typo is rejected at creation rather than
producing a row that quietly never matches. An organization cannot have two destinations claiming
the same event type, because the lookup would then be ambiguous.

> The overlap rule is enforced in the model, not in the database. Postgres has no GiST operator
> class for `varchar[]`, so the exclusion constraint the design called for cannot be created, and
> GIN backs neither exclusion constraints nor unique indexes. A row written with `insert_all` or
> `update_column` can still create an overlap.

## Verifying it before real usage flows

```bash
bundle exec rails "streaming_destinations:verify[<organization uuid>]"
```

It prints the destination back, asks you to confirm the ARN's account against the organization,
then delivers one customer's usage on demand and tells you what to look for. A line with
`outcome=delivered` carrying a shard and a sequence number means the record landed. `outcome=dropped`
means it did not, and the `error` field says why.

Do this on a customer whose usage you can recognise, and confirm with whoever owns the stream
that the record arrived on the stream you think you configured, not merely on some stream.

## Changing or removing one

Deleting the row stops delivery immediately and completely. It is the off switch.

Changing `role_arn` takes effect on the next process, not the next delivery: assumed credentials
are cached per process for the lifetime of the role ARN. Restart the streaming workers after
changing one.

## How delivery behaves

Worth knowing before you promise anything to a consumer:

- **Best-effort latest state, not at-least-once.** If two refreshes for one customer land close
  together, the freshest one is delivered and the other is dropped. A dropped snapshot is never
  redelivered; the next wallet refresh supersedes it.
- **Records carry a `version`,** a fixed-width UTC timestamp captured at read time and shared by
  every subscription in one delivery. A consumer should drop any record whose version is less
  than or equal to one it already holds, per
  `(organization_id, customer_external_id, subscription_external_id)`.
- **Failures never surface as failed jobs.** Every failure mode is logged per subscription while
  the job still succeeds. Monitoring is therefore not optional:
  `docs/streaming_delivery_monitoring.md`.
- **Deliveries run on their own Sidekiq queue,** `streaming`, consumed by
  `scripts/start.streaming.worker.sh`. That worker needs the AWS identity. If nothing consumes
  the queue, jobs pile up rather than disappearing.

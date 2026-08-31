# [BE] BillingPeriodFilters Refactor

<table_of_contents color="gray"/>

# Context {color="orange_bg"}

`Events::BillingPeriodFilterService` prefilters billable events before fee calculation. Today it returns charge/filter buckets that should be aggregated for a billing period.

This prefiltering step is deliberately separate from fee computation. Its output only answers one question: for a given billing period, which event filter buckets are relevant for each billable target? The fee services then use that output as `filtered_aggregations` to avoid computing unused aggregation buckets.

Current legacy usage:

```ruby
filters = event_filters(subscription, boundaries).charges

filtered_aggregations: filters[charge.id]&.keys || []
```

Target usage after the refactor:

```ruby
filters = event_filters(subscription, boundaries).filter_targets

filtered_aggregations: filters[charge.target_key]&.keys || []
```

The service currently assumes legacy charge billing concepts:

- `subscription.plan`
- `plan.charges`
- `ChargeFilters::EventMatchingService`
- `ChargeFilters::MatchingAndIgnoredService`
- `charge_id`
- `charge_filter_id`
- previous fees with `fee_type: :charge`

Product-catalog billing needs the same event prefiltering behavior, but the source model is different:

- `billing_cycles`
- `contract_rate_card.product`
- product filters instead of charge filters
- `product.target_key` target keys
- `product_filter_id` inner keys
- previous fees with `fee_type: :product`

Adding product-catalog conditionals directly to `Events::BillingPeriodFilterService` would make the legacy service responsible for two different input models. The refactor should instead keep explicit public entrypoints, use a small `case` where resolver selection is needed, and let shared matching services operate on a small PORO contract.

## Known issues {color="gray_bg"}

- The current service result is charge-shaped (`charges`) even though product-catalog billing needs the same logical result for products.
- The matching services live under `ChargeFilters::*`, which makes product-filter reuse look like a new parallel namespace instead of shared event-filter behavior.
- The pre-enriched event path is charge-specific because it returns `charge_id` and `charge_filter_id` pairs.
- Some charges have very large filter counts. The common case is small, but production outliers make repeated full scans expensive.

# Goal {color="orange_bg"}

## Abstract {color="gray_bg"}

Refactor billing-period event filtering around a generic `FilterTarget` contract. The first step preserves the legacy charge behavior while changing the result field to `filter_targets`. A later step adds billing-cycle/product-filter support through a separate adapter, without branching inside the legacy entrypoint or duplicating the matching services.

## Design decisions {color="gray_bg"}

> ✅ **Decision** — Return `filter_targets`, not `targets`.
>
> **Why:** The result contains billing-period event-filter targets, not arbitrary domain targets. The explicit name makes callers read the output as filter preselection data and avoids ambiguity with products, charges, or billing cycles themselves.

> ✅ **Decision** — Use `FilterTarget` as the shared matching contract.
>
> **Why:** `Filter` is overloaded by `ChargeFilter` and `ProductFilter`, while `FilterTarget` describes the object being matched against an event. It gives shared services one vocabulary across charge-backed and billing-cycle-backed sources.

> ✅ **Decision** — Keep phase 1 charge-only and behavior-preserving.
>
> **Why:** Product-catalog support changes the source model, persisted fee type, and target key shape. Shipping the charge adapter first makes the public result change and matching-service extraction easier to verify independently.

> ✅ **Decision** — Do not reuse `Fees::ChargeService::MeteredItem` for event prefiltering.
>
> **Why:** `MeteredItem` is a fee-computation adapter. Event prefiltering needs billable metric filters, filter values, target keys, and selected-filter overlap semantics before fee calculation starts.

> ✅ **Decision** — Do not introduce `ProductFilters::*` matching services.
>
> **Why:** Product filters and charge filters need the same matching algorithm. A shared `Events::BillingPeriodFilters::*` namespace prevents two implementations from drifting.

> ✅ **Decision** — Add model-level `target_key` methods for event-filter keys.
>
> **Why:** The outer hash key is a transient event-filter lookup key. Keeping the string format on the model avoids duplicating interpolation across services, makes the key discoverable, and keeps callers from relying on billing-cycle ids or source-specific filter keys.

> ✅ **Decision** — Keep indexed matching as an optimization phase.
>
> **Why:** Production data shows the common case is small, so the linear scan is easier to reason about and should remain the default path until the shared behavior is stable.

## Goals {color="gray_bg"}

- Keep one result field: `filter_targets`.
- Introduce `Events::BillingPeriodFilters::FilterTarget` for event prefiltering only.
- Support charge-backed targets first without changing billing output.
- Add billing-cycle-backed targets after the charge-backed refactor is stable.
- Avoid reusing `Fees::ChargeService::MeteredItem` for event prefiltering.
- Avoid introducing duplicate `ProductFilters::*` matching services.
- Avoid using billing-cycle `id` or a custom `filter_key` as the event-filter target key.

## Out of scope {color="gray_bg"}

- Changing fee persistence, idempotency, invoiceable ids, or aggregation semantics.
- Replacing `Fees::ChargeService::MeteredItem` or changing fee-calculation behavior.
- Introducing product-catalog billing in phase 1.
- Reworking the event-store API beyond the adapter calls described here.
- Renaming persisted product types or product-filter model fields.

# Technical proposal {color="orange_bg"}

<callout icon="⚠️" color="gray_bg">
  A dive-in is not about code review. This document captures service boundaries, key decisions, and task breakdown; exact implementation details should still be reviewed in GitHub pull requests.
</callout>

## Existing behavior {color="gray_bg"}

`Events::BillingPeriodFilterService` currently has two event lookup paths.

The non-pre-enriched path calls:

```ruby
event_store.distinct_codes_and_property_combinations(
  codes: non_recurring_plan_codes,
  filter_keys: billable_metric_filter_keys,
  with_last_seen_at:
)
```

Then it matches each returned event-property combination against the charge filters:

```ruby
event = ::Event.new(code:, properties:)
matching = ChargeFilters::EventMatchingService.call(charge:, event:).matching_charge_filters
```

If no filter matches, usage goes into the default bucket:

```ruby
record(result, charge.id, nil, last_seen_at)
```

If filters match, every matching filter is recorded and later aggregation rules make the most-specific bucket win:

```ruby
matching.each { |filter| record(result, charge.id, filter.id, last_seen_at) }
```

The pre-enriched path calls:

```ruby
event_store.distinct_charges_and_filters(
  codes: non_recurring_plan_codes,
  with_last_seen_at:
)
```

That path is charge-specific because it returns `charge_id` and `charge_filter_id` pairs from pre-enriched events.

Recurring billable metrics are seeded so usage can carry over from previous periods. Current charge behavior must remain unchanged after phase 1.

## General design {color="gray_bg"}

```text
Events::BillingPeriodFilterService
  -> legacy charge entrypoint returning `filter_targets`

Events::BillingPeriodFilters::BillingCyclesService
  -> product-catalog billing-cycle entrypoint returning `filter_targets`

Events::BillingPeriodFilters::ChargesResolver
  -> builds charge-backed FilterTarget objects

Events::BillingPeriodFilters::BillingCyclesResolver
  -> builds billing-cycle-backed FilterTarget objects

Events::BillingPeriodFilters::FilterTarget
  -> PORO exposing filter dependencies for either a Charge/ChargeFilter or BillingCycle/ProductFilter

Events::BillingPeriodFilters::EventMatchingService
  -> matches an event against a FilterTarget

Events::BillingPeriodFilters::MatchingAndIgnoredService
  -> resolves matching/ignored filters for one selected FilterTarget
```

**Context:** Both legacy charges and product-catalog billing cycles need the same logical operations: load candidate billable targets, match event properties against their filters, record the matching filter ids, and account for ignored filters when one filter makes another bucket redundant.

The resolver boundary should stay simple: public services build the correct resolver and return `resolver.filter_targets`. If a generic path must select between resolvers, use a local `case` expression instead of introducing a dedicated service object just to forward `filter_targets`.

```ruby
resolver = case source
when :charges
  Events::BillingPeriodFilters::ChargesResolver.new(...)
when :billing_cycles
  Events::BillingPeriodFilters::BillingCyclesResolver.new(...)
else
  raise ArgumentError, "unsupported billing-period filter source: #{source}"
end

result.filter_targets = resolver.filter_targets
```

Phase 1 only introduces the charge-backed part of this structure. Phase 2 adds the billing-cycle entrypoint, adapter, source, and `FilterTarget.from_billing_cycle` constructor.

## Result shape {color="gray_bg"}

Charge-backed result:

```ruby
{
  charge.target_key => {
    charge_filter_id_or_nil => last_seen_at
  }
}
```

`target_key` is only for billing-period event filtering and for looking up `filtered_aggregations` before fee calculation. It must not be used as a persisted identifier, fee idempotency key, or invoiceable id.

> ✅ **Decision** — Keep the inner key as the source filter id or `nil`.
>
> **Why:** Existing fee aggregation already understands selected filter ids and the synthetic default bucket. Changing only the outer key keeps the refactor focused on the billing target boundary.

## Authorization change {color="gray_bg"}

No authorization change is expected.

**Permissions**

- No new UI action is introduced.
- No existing permission check changes.

**API Key scopes**

- No REST API scope is added or changed.

## Database update {color="gray_bg"}

No database change is expected.

### Table changes

- None.

### Index changes

- None.

### Constraints

- None.

### Enums

- None.

## Data migration / back-fill {color="gray_bg"}

No data migration or backfill is expected.

- The result shape changes at runtime only.
- Existing fees, charge filters, product filters, billing cycles, and events stay unchanged.
- No historical rows need to be rewritten because `target_key` is not persisted.

## Model changes {color="gray_bg"}

Add model-level target-key helpers for billable event-filter targets.

- `Charge#target_key` returns the charge-backed event-filter key.
- `Product#target_key` returns the product-backed event-filter key.
- `ChargeFilter`, `ProductFilter`, and `BillingCycle` do not need their own event-filter target keys.
- `FilterTarget` and source resolvers are PORO/service-layer objects only.

```ruby
class Charge < ApplicationRecord
  def target_key
    "charge-#{id}"
  end
end
```

```ruby
class Product < ApplicationRecord
  def target_key
    "product-#{id}"
  end
end
```

## REST API changes {color="gray_bg"}

No REST API change is expected for this refactor.

- The billing-period filter result is consumed internally by fee and current-usage services.
- Public API payloads should remain unchanged unless downstream product-catalog current-usage work explicitly changes them in a separate dive-in.

## Webhook changes {color="gray_bg"}

No webhook change is expected.

- No new webhook event is introduced.
- No existing webhook payload changes.

## **GraphQL** API changes {color="gray_bg"}

No GraphQL API change is expected.

- No query, mutation, type, input, or resolver change is part of this refactor.

## View / PDF template changes {color="gray_bg"}

No view or PDF template change is expected.

- Invoice rendering should keep reading persisted fees, not billing-period filter internals.
- Historical invoices are unaffected.

## Other changes {color="gray_bg"}

- [ ] OpenAPI update: not needed for this internal service refactor.
- [ ] Client library update: not needed.
- [ ] Documentation update: this BE Dive document.

## Service changes {color="gray_bg"}

The implementation work is split by risk. Phase 1 makes the charge path generic without adding product-catalog behavior. Phase 2 adds billing-cycle support. Phases 3 and 4 are optional optimization passes backed by production filter-count data.

### Phase 1: Charge-backed FilterTarget

Phase 1 extracts the current charge behavior behind `Events::BillingPeriodFilters::FilterTarget` and `Events::BillingPeriodFilters::ChargesResolver`. This should be behavior-preserving.

**Context:** This phase is intentionally a shape and ownership refactor. The service should still read the same plan charges, call the same event-store methods, seed recurring metrics the same way, and produce the same charge-filter buckets under prefixed charge target keys.

> ✅ **Decision** — Keep `Events::BillingPeriodFilterService` as the legacy public entrypoint.
>
> **Why:** Existing invoice and current-usage flows should not need to understand the new adapter layer. They only need to read the renamed result field and use the prefixed charge key.

#### What Changes

- Change `Events::BillingPeriodFilterService::Result` from source-specific data to `BaseResult[:filter_targets]`.
- Move the current charge-specific logic into `Events::BillingPeriodFilters::ChargesResolver`.
- Add `Events::BillingPeriodFilters::FilterTarget` with charge-backed source support.
- Move reusable event matching into `Events::BillingPeriodFilters::EventMatchingService`.
- Move reusable matching/ignored-filter logic into `Events::BillingPeriodFilters::MatchingAndIgnoredService`.
- Keep `ChargeFilters::EventMatchingService` and `ChargeFilters::MatchingAndIgnoredService` as compatibility wrappers.
- Update callers to read `.filter_targets` instead of `.charges`.
- Update filtered aggregation lookups from `filters[charge.id]` to `filters[charge.target_key]`.

#### Affected Classes

- `app/services/events/billing_period_filter_service.rb`
- `app/services/events/billing_period_filters/filter_target.rb`
- `app/services/events/billing_period_filters/sources/charge.rb`
- `app/services/events/billing_period_filters/charges_resolver.rb`
- `app/services/events/billing_period_filters/event_matching_service.rb`
- `app/services/events/billing_period_filters/matching_and_ignored_service.rb`
- `app/services/charge_filters/event_matching_service.rb`
- `app/services/charge_filters/matching_and_ignored_service.rb`

Affected callers include services that call `Events::BillingPeriodFilterService` or use its result:

- `app/services/invoices/calculate_fees_service.rb`
- `app/services/invoices/customer_usage_service.rb`
- other invoice/current-usage services that currently read `event_filters(...).charges`

#### Legacy Entrypoint

The legacy entrypoint builds a charge-backed adapter and delegates the full filtering flow. It should not know how charge filters are loaded, matched, or recorded.

```ruby
module Events
  class BillingPeriodFilterService < BaseService
    Result = BaseResult[:filter_targets]

    def initialize(subscription:, boundaries:, codes: nil, with_last_seen_at: true)
      @subscription = subscription
      @boundaries = boundaries
      @codes = codes
      @with_last_seen_at = with_last_seen_at
      super
    end

    def call
      resolver = BillingPeriodFilters::ChargesResolver.new(
        subscription:,
        boundaries:,
        codes:,
        with_last_seen_at:
      )

      result.filter_targets = resolver.filter_targets
      result
    end

    private

    attr_reader :subscription, :boundaries, :codes, :with_last_seen_at
  end
end
```

#### FilterTarget PORO

`FilterTarget` is the stable contract consumed by shared matching services. The services should not ask whether the source is a `Charge`, `BillingCycle`, `ChargeFilter`, or `ProductFilter`.

```ruby
module Events
  module BillingPeriodFilters
    FilterTarget = Data.define(:source) do
      def self.from_charge(charge:, filter: nil)
        new(source: Sources::Charge.new(charge:, filter:))
      end

      delegate :billable_metric,
        :filters,
        :selected_filter,
        :filter_values,
        :filter_match_values,
        :filter_specificity,
        :all_filter_values?,
        :target_key,
        :with_filter,
        to: :source
    end
  end
end
```

#### Charge Source

The charge source adapts existing charge methods to the `FilterTarget` contract. It keeps charge-specific details such as `ChargeFilter#to_h_with_all_values` out of the generic matching services.

```ruby
module Events
  module BillingPeriodFilters
    module Sources
      Charge = Data.define(:charge, :filter) do
        delegate :billable_metric, to: :charge

        def filters
          return charge.filters if charge.association_cached?(:filters)

          charge.filters.includes(values: :billable_metric_filter)
        end

        def selected_filter
          filter
        end

        def filter_values(filter)
          filter.to_h_with_all_values
        end

        def filter_match_values(filter)
          filter.to_h
        end

        def filter_specificity(filter)
          filter.to_h.keys.size
        end

        def all_filter_values?(filter, key)
          filter.to_h[key] == [ChargeFilterValue::ALL_FILTER_VALUES]
        end

        def target_key
          charge.target_key
        end

        def with_filter(filter)
          self.class.new(charge:, filter:)
        end
      end
    end
  end
end
```

#### Generic Event Matching

Keep the first refactor simple and behavior-preserving. `EventMatchingService` should keep the current linear scan and operate through the `FilterTarget` contract.

Event matching remains exact. Even after the optimization phase adds indexes, candidate lookup only narrows the scan; the final match condition must stay the same.

```ruby
module Events
  module BillingPeriodFilters
    class EventMatchingService < BaseService
      Result = BaseResult[:matching_filters, :filter]

      def initialize(target:, event:)
        @target = target
        @event = event
        super
      end

      def call
        matching_filters = target.filters.select do |filter|
          target.filter_values(filter).all? do |key, values|
            applicable_event_properties.key?(key) && applicable_event_properties[key].to_s.in?(values.map(&:to_s))
          end
        end

        result.matching_filters = matching_filters
        result.filter = matching_filters.max_by { |filter| target.filter_specificity(filter) }
        result
      end

      private

      attr_reader :target, :event

      def applicable_event_properties
        @applicable_event_properties ||= event.properties.slice(*billable_metric_filter_keys)
      end

      def billable_metric_filter_keys
        billable_metric = target.billable_metric

        return billable_metric.filters.map(&:key) if billable_metric.association_cached?(:filters)

        billable_metric.filters.pluck(:key)
      end
    end
  end
end
```

#### Generic Matching And Ignored Filters

Ignored-filter detection preserves the existing charge-filter semantics. The selected filter is used as the parent, overlapping child filters are discovered, and redundant buckets are removed so aggregation does not double-count.

```ruby
module Events
  module BillingPeriodFilters
    class MatchingAndIgnoredService < BaseService
      Result = BaseResult[:matching_filters, :ignored_filters]

      def initialize(target:)
        @target = target
        super
      end

      def call
        selected_filter = target.selected_filter
        result.matching_filters = target.filter_values(selected_filter)

        children = other_filters.find_all do |filter|
          child = target.filter_values(filter)

          result.matching_filters.all? do |key, values|
            values.any? { (child[key] || []).include?(it) }
          end
        end

        result.ignored_filters = children.map do |child_filter|
          child = target.filter_values(child_filter).dup

          if child.keys.sort == result.matching_filters.keys.sort
            if identical_to_matching_filters?(child)
              next unless older_than_filter?(child_filter, selected_filter)
            elsif !subset_of_matching_filters?(child)
              child.each do |key, values|
                next if target.all_filter_values?(selected_filter, key)

                child[key] = values - result.matching_filters[key]
              end
            end
          end

          child
        end.compact

        result
      end

      private

      attr_reader :target

      def other_filters
        target.filters.reject { it.id == target.selected_filter.id }
      end

      def subset_of_matching_filters?(child)
        child.all? { |key, values| (values - result.matching_filters[key]).empty? }
      end

      def identical_to_matching_filters?(child)
        child.all? { |key, values| values.sort == result.matching_filters[key].sort }
      end

      def older_than_filter?(child, selected_filter)
        return true if selected_filter.created_at.nil?

        ([child.created_at, child.id] <=> [selected_filter.created_at, selected_filter.id]).negative?
      end
    end
  end
end
```

#### ChargeFilters Compatibility Wrappers

Keep existing public APIs so unrelated callers can be migrated separately.

These wrappers make `Events::BillingPeriodFilters::*` the implementation source of truth while preserving the old return names for callers that still speak in charge-filter terms.

```ruby
module ChargeFilters
  class EventMatchingService < BaseService
    Result = BaseResult[:matching_charge_filters, :charge_filter]

    def initialize(charge:, event:)
      @charge = charge
      @event = event
      super
    end

    def call
      matching_result = Events::BillingPeriodFilters::EventMatchingService.call(
        target: Events::BillingPeriodFilters::FilterTarget.from_charge(charge:),
        event:
      )

      result.matching_charge_filters = matching_result.matching_filters
      result.charge_filter = matching_result.filter
      result
    end

    private

    attr_reader :charge, :event
  end
end
```

```ruby
target = Events::BillingPeriodFilters::FilterTarget.from_charge(
  charge:,
  filter:
)

matching_result = Events::BillingPeriodFilters::MatchingAndIgnoredService.call(
  target:
)
```

#### ChargesResolver Behavior

`ChargesResolver` should preserve the current `Events::BillingPeriodFilterService` logic, but write charge-backed target keys:

`ChargesResolver` owns orchestration for the charge-backed path: event-store queries, charge target construction, recurring metric seeding, matching calls, and recording into the final `filter_targets` hash.

```ruby
target = Events::BillingPeriodFilters::FilterTarget.from_charge(charge:)
event = Event.new(code:, properties:)
matching = Events::BillingPeriodFilters::EventMatchingService.call(
  target:,
  event:
).matching_filters

if matching.empty?
  record(result, target.target_key, nil, last_seen_at)
else
  matching.each { |filter| record(result, target.target_key, filter.id, last_seen_at) }
end
```

The adapter owns:

- resolving `plan_codes`
- creating the event store
- loading charges for matching events
- seeding recurring charges
- reading previous recurring fees
- preserving `with_last_seen_at` behavior
- preserving pre-enriched event behavior for charge-backed targets

### Phase 2: Billing-cycle support

Phase 2 adds product-catalog billing-cycle event prefiltering without changing the charge-backed path.

**Context:** Billing cycles are persisted product-catalog billing work items. For metered products, they need the same event prefiltering as charges, but the target comes from `contract_rate_card.product` and selected filters come from `ProductFilter`.

> ✅ **Decision** — Add a separate `BillingCyclesService` entrypoint.
>
> **Why:** The legacy subscription/plan charge flow and product-catalog billing-cycle flow start from different inputs. Separate public services keep each caller explicit while sharing resolvers and matchers underneath.

> ✅ **Decision** — Use product ids, not billing-cycle ids, for target keys.
>
> **Why:** The aggregation target is the product's billable metric/filter set. Billing cycles represent period work and should not become event-filter bucket identifiers.

#### What Changes

- Add `Events::BillingPeriodFilters::BillingCyclesService` as the billing-cycle public entrypoint.
- Add `Events::BillingPeriodFilters::BillingCyclesResolver`.
- Add `Events::BillingPeriodFilters::Sources::BillingCycle` for `FilterTarget.from_billing_cycle`.
- Use the same `EventMatchingService` and `MatchingAndIgnoredService` from phase 1.
- Return product-keyed `filter_targets` using `product.target_key`.
- Use inner keys as `product_filter.id` or `nil`.
- Use `distinct_codes_and_property_combinations` for billing cycles.
- Do not use `distinct_charges_and_filters` for billing cycles.
- Do not use `billing_cycle.id` or `billing_cycle.filter_key` as the event-filter target key.

#### Affected Classes

- `app/services/events/billing_period_filters/billing_cycles_service.rb`
- `app/services/events/billing_period_filters/billing_cycles_resolver.rb`
- `app/services/events/billing_period_filters/sources/billing_cycle.rb`
- `app/services/events/billing_period_filters/filter_target.rb`
- `app/services/events/billing_period_filters/event_matching_service.rb`
- `app/services/events/billing_period_filters/matching_and_ignored_service.rb`

Affected downstream services include:

- `app/services/billing_cycles/fees/metered_compute_service.rb`
- contract current-usage services that build billing-cycle-shaped candidates
- any service that needs product-catalog `filtered_aggregations`

#### Target Result Shape

Billing-cycle-backed result:

```ruby
{
  product.target_key => {
    product_filter_id_or_nil => last_seen_at
  }
}
```

Current-usage billing-cycle candidates use the same product target key:

```ruby
{
  product.target_key => {
    product_filter_id_or_nil => nil
  }
}
```

Do not use `billing_cycle.id` or `billing_cycle.filter_key` for this event-filtering key. Billing-cycle-backed filtering uses `product.target_key` because the matching dependency is the product's billable metric and product filters, not the billing cycle row.

#### BillingCyclesService

The billing-cycle entrypoint accepts a collection of cycles and delegates to the shared resolver. It mirrors the legacy entrypoint but starts from product-catalog period records instead of a subscription plan.

```ruby
module Events
  module BillingPeriodFilters
    class BillingCyclesService < BaseService
      Result = BaseResult[:filter_targets]

      def initialize(contract:, billing_cycles:, codes: nil, with_last_seen_at: true)
        @contract = contract
        @billing_cycles = billing_cycles
        @codes = codes
        @with_last_seen_at = with_last_seen_at
        super
      end

      def call
        resolver = BillingCyclesResolver.new(
          contract:,
          billing_cycles:,
          codes:,
          with_last_seen_at:
        )

        result.filter_targets = resolver.filter_targets
        result
      end

      private

      attr_reader :contract, :billing_cycles, :codes, :with_last_seen_at
    end
  end
end
```

#### BillingCycle Source

The billing-cycle source adapts `contract_rate_card.product` and `ProductFilter` to the same `FilterTarget` methods used by charge-backed matching.

Extend `FilterTarget` in this phase only:

```ruby
module Events
  module BillingPeriodFilters
    class FilterTarget
      def self.from_billing_cycle(billing_cycle:, filter: nil)
        new(source: Sources::BillingCycle.new(billing_cycle:, filter:))
      end
    end
  end
end
```

Then add the billing-cycle-backed source:

```ruby
module Events
  module BillingPeriodFilters
    module Sources
      BillingCycle = Data.define(:billing_cycle, :filter) do
        def billable_metric
          product.billable_metric
        end

        def filters
          return product.filters if product.association_cached?(:filters)

          product.filters.includes(values: :billable_metric_filter)
        end

        def selected_filter
          filter
        end

        def filter_values(filter)
          filter.to_h
        end

        def filter_match_values(filter)
          filter.to_h
        end

        def filter_specificity(filter)
          filter.to_h.keys.size
        end

        def all_filter_values?(_filter, _key)
          false
        end

        def target_key
          product.target_key
        end

        def with_filter(filter)
          self.class.new(billing_cycle:, filter:)
        end

        private

        def product
          billing_cycle.contract_rate_card.product
        end
      end
    end
  end
end
```

#### BillingCyclesResolver Behavior

The billing-cycle adapter should mirror the charge adapter's non-pre-enriched lookup shape:

Product-specific work is limited to source construction and product-keyed output. Matching and ignored-filter behavior should remain delegated to the shared services.

```ruby
combinations = event_store.distinct_codes_and_property_combinations(
  codes: non_recurring_product_codes,
  filter_keys: billable_metric_filter_keys,
  with_last_seen_at:
)
```

It should group combinations by billable metric code, load billing cycles for products with matching metrics, and use the generic matcher:

```ruby
target = Events::BillingPeriodFilters::FilterTarget.from_billing_cycle(billing_cycle:)
event = Event.new(code:, properties:)
matching = Events::BillingPeriodFilters::EventMatchingService.call(
  target:,
  event:
).matching_filters

if matching.empty?
  record(result, target.target_key, nil, last_seen_at)
else
  matching.each { |filter| record(result, target.target_key, filter.id, last_seen_at) }
end
```

For current usage, downstream services should look up filtered aggregations with the same key convention:

```ruby
target = Events::BillingPeriodFilters::FilterTarget.from_billing_cycle(billing_cycle:)

filtered_aggregations: filtered_aggregations[target.target_key]&.keys || []
```

### Phase 3: EventMatchingService optimization

Phase 3 should optimize only `Events::BillingPeriodFilters::EventMatchingService`. Do not change `MatchingAndIgnoredService` in this step.

**Context:** The phase 1 matcher keeps the exact current algorithm and scans every filter for a target. That is acceptable for the common case, but expensive for high-filter-count charges that repeat the same scan for many event-property combinations.

> ✅ **Decision** — Keep linear matching below `INDEX_THRESHOLD`.
>
> **Why:** Most production targets have very few filters. Building an index for those targets adds allocation and complexity without meaningful benefit.

> ✅ **Decision** — Use the index only for candidate discovery, then run exact matching.
>
> **Why:** Candidate lookup is an optimization detail. The final result must remain identical to the linear scan, especially for broader filters when an event carries extra properties.

#### Production Data Context

The production sample in `tmp/query_result_2026-08-28T14_04_27.825319051Z.json` contains charge ids and their charge-filter counts.

Observed distribution:

| Metric | Filter count |
| --- | ---: |
| Total rows | 1,048,575 |
| Min | 2 |
| p50 | 3 |
| p75 | 5 |
| p90 | 18 |
| p95 | 148 |
| p99 | 180 |
| Max | 18,452 |

Bucketed distribution:

| Filter count | Charges |
| --- | ---: |
| 1-9 | 929,857 |
| 10-99 | 51,067 |
| 100-499 | 67,446 |
| 500-999 | 25 |
| 1,000-4,999 | 142 |
| 5,000-9,999 | 10 |
| 10,000+ | 28 |

The common case is small: most charges have fewer than 10 filters. The risk is the outlier path: a small number of charges have thousands of filters, and the current linear scan repeats for every event-property combination.

#### Current Cost

The current matcher is simple and correct:

```ruby
matching_filters = target.filters.select do |filter|
  target.filter_values(filter).all? do |key, values|
    applicable_event_properties.key?(key) && applicable_event_properties[key].to_s.in?(values.map(&:to_s))
  end
end
```

Cost per target is roughly:

```text
event_property_combinations * target.filters.size * average_filter_width
```

This is acceptable for 10 filters and usually fine for 100 filters. It is risky for the observed outliers around 3K, 10K, and 18K filters.

#### Recommended Approach

Keep the linear scan as the default. Add indexed matching only when a target has enough filters to justify the index build cost.

The threshold should be deliberately conservative at first.

Initial threshold:

```ruby
INDEX_THRESHOLD = 100
```

Rationale:

- p90 is 18, so most targets keep the simpler linear path.
- p95 is 148, so the threshold starts near the point where scans become more expensive.
- charges above 1K benefit substantially.
- 10-filter targets avoid unnecessary index allocation.
- 100-filter targets are borderline, but indexing becomes useful when there are many event-property combinations for the same target.

#### What Changes

- Add an optional index path inside `Events::BillingPeriodFilters::EventMatchingService` only.
- Keep the public service API stable: `target:` and `event:`.
- Add a reusable `Events::BillingPeriodFilters::FilterIndex` value object.
- Let resolvers cache one `FilterIndex` per `target_key` and pass it as `filter_index:`.
- Keep exact validation after index lookup so behavior stays identical to the linear scan.
- Do not change `MatchingAndIgnoredService`.

#### Indexed Matching Shape

Build an in-memory index from filter key/value to filters:

```ruby
{
  "region" => {
    "eu" => [filter_1, filter_2],
    "us" => [filter_3]
  },
  "cloud" => {
    "aws" => [filter_1, filter_4]
  }
}
```

Candidate selection should union candidate filters for the event's applicable key/value pairs, not intersect them. An event can contain more properties than a filter requires, so intersecting across every event property would incorrectly drop broader filters.

Use arrays for candidate collection and call `uniq` once at the end. The candidate list is only an intermediate optimization path, so `Set` is unnecessary here.

```ruby
def candidates_matching_any(properties)
  properties.flat_map do |key, value|
    index.fetch(key, {})[value.to_s]
  end.compact.uniq
end
```

Only consider a different data structure later if profiling shows candidate deduplication itself is significant.

#### Shared FilterIndex

`FilterIndex` should be reusable by both optimized matching services. Phase 3 uses `candidates_matching_any` for event matching. Phase 4 reuses the same index with `candidates_overlapping_all` for ignored-filter discovery.

> ✅ **Decision** — Implement one shared `FilterIndex` class.
>
> **Why:** Both optimizations need the same key/value-to-filter lookup. Sharing the index avoids two subtly different implementations and lets resolvers cache one index per `target_key`.

```ruby
module Events
  module BillingPeriodFilters
    FilterIndex = Data.define(:target) do
      def candidates_matching_any(properties)
        properties.flat_map do |key, value|
          index.fetch(key, {})[value.to_s]
        end.compact.uniq
      end

      def candidates_overlapping_all(filter_values)
        candidate_sets = filter_values.filter_map do |key, values|
          candidates_matching_any_value(key, values)
        end

        return [] if candidate_sets.empty?

        candidate_sets.reduce { |memo, candidates| memo & candidates }
      end

      private

      def candidates_matching_any_value(key, values)
        values.flat_map do |value|
          index.fetch(key, {})[value.to_s]
        end.compact.uniq
      end

      def index
        @index ||= target.filters.each_with_object({}) do |filter, accumulator|
          target.filter_values(filter).each do |key, values|
            values.each do |value|
              accumulator[key] ||= {}
              accumulator[key][value.to_s] ||= []
              accumulator[key][value.to_s] << filter
            end
          end
        end
      end
    end
  end
end
```

#### EventMatchingService Example

```ruby
module Events
  module BillingPeriodFilters
    class EventMatchingService < BaseService
      INDEX_THRESHOLD = 100

      Result = BaseResult[:matching_filters, :filter]

      def initialize(target:, event:, filter_index: nil)
        @target = target
        @event = event
        @filter_index = filter_index
        super
      end

      def call
        matching_filters = filters_to_scan.select { |filter| matches?(filter) }

        result.matching_filters = matching_filters
        result.filter = matching_filters.max_by { |filter| target.filter_specificity(filter) }
        result
      end

      private

      attr_reader :target, :event, :filter_index

      def filters_to_scan
        return target.filters unless indexed_matching?

        indexed_candidate_filters
      end

      def indexed_matching?
        target.filters.size >= INDEX_THRESHOLD
      end

      def indexed_candidate_filters
        return [] if applicable_event_properties.empty?

        (filter_index || Events::BillingPeriodFilters::FilterIndex.new(target:)).candidates_matching_any(applicable_event_properties)
      end

      def matches?(filter)
        target.filter_values(filter).all? do |key, values|
          applicable_event_properties.key?(key) && applicable_event_properties[key].to_s.in?(values.map(&:to_s))
        end
      end

      def applicable_event_properties
        @applicable_event_properties ||= event.properties.slice(*billable_metric_filter_keys)
      end

      def billable_metric_filter_keys
        billable_metric = target.billable_metric

        return billable_metric.filters.map(&:key) if billable_metric.association_cached?(:filters)

        billable_metric.filters.pluck(:key)
      end
    end
  end
end
```

Resolvers should cache one index per target so the index is not rebuilt for each event-property combination:

```ruby
def filter_index_for(target)
  return nil if target.filters.size < Events::BillingPeriodFilters::EventMatchingService::INDEX_THRESHOLD

  filter_indexes[target.target_key] ||= Events::BillingPeriodFilters::FilterIndex.new(target:)
end

def filter_indexes
  @filter_indexes ||= {}
end
```

Then resolver calls pass the cached index without changing matching behavior:

```ruby
matching = Events::BillingPeriodFilters::EventMatchingService.call(
  target:,
  event:,
  filter_index: filter_index_for(target)
).matching_filters
```

#### Affected Classes

- `app/services/events/billing_period_filters/event_matching_service.rb`
- `app/services/events/billing_period_filters/filter_index.rb`
- `app/services/events/billing_period_filters/charges_resolver.rb`
- `app/services/events/billing_period_filters/billing_cycles_resolver.rb`

No `MatchingAndIgnoredService` changes should be made in this phase.

#### Verification

Focused specs:

```bash
lago exec api bundle exec rspec spec/services/events/billing_period_filters/event_matching_service_spec.rb
```

Key assertions:

- below `INDEX_THRESHOLD`, the service uses the linear scan path.
- at or above `INDEX_THRESHOLD`, the service uses indexed candidates.
- indexed matching returns the same filters as the linear scan.
- indexed matching still returns broader filters when an event contains additional properties.
- indexed matching returns the most specific selected filter with the same tie behavior as today.
- no `MatchingAndIgnoredService` behavior changes in this phase.

### Phase 4: MatchingAndIgnoredService optimization

Phase 4 should consider the same production shape for `Events::BillingPeriodFilters::MatchingAndIgnoredService`. This service also scans the full filter collection for each selected filter, which is risky for the same high-filter-count charge outliers.

**Context:** `MatchingAndIgnoredService` runs after a filter has already been selected. Its job is different from event matching: it finds other filters that overlap the selected filter on every selected key, then prunes ignored buckets. The same index can reduce the candidate list, but the candidate-selection rule must be intersection-based, not union-based.

> ✅ **Decision** — Reuse the phase 3 `FilterIndex` instead of adding a second index.
>
> **Why:** The underlying lookup structure is identical. Only the query method differs: event matching unions candidates by event properties, while ignored-filter matching intersects candidates by selected filter keys.

#### Current Cost

The current matcher is simple and correct:

```ruby
children = other_filters.find_all do |filter|
  child = target.filter_values(filter)

  result.matching_filters.all? do |key, values|
    values.any? { (child[key] || []).include?(it) }
  end
end
```

Cost per selected filter is roughly:

```text
target.filters.size * selected_filter_width * average_child_filter_width
```

This is fine for the common case from the sample: p50 is 3 filters and p90 is 18 filters. It becomes expensive for the same outliers where one charge has thousands of charge filters.

#### Recommended Approach

Keep the linear scan as the default and add indexed child-filter discovery only above the same threshold used by `EventMatchingService`.

Initial threshold:

```ruby
INDEX_THRESHOLD = Events::BillingPeriodFilters::EventMatchingService::INDEX_THRESHOLD
```

The index should reuse `Events::BillingPeriodFilters::FilterIndex` from phase 3 with the same charge + charge-filter set already loaded through `FilterTarget`. It should not query a separate data source or change the selected-filter semantics.

Candidate selection should work differently from event matching:

- for each selected filter key, union filters matching any selected value for that key
- intersect the per-key sets so candidates match at least one selected value for every selected key
- remove the selected filter itself
- run the existing exact validation and ignored-filter pruning on only those candidates

This preserves the current behavior because `MatchingAndIgnoredService` only considers children that overlap the selected filter on every selected key.

#### MatchingAndIgnoredService Example

```ruby
module Events
  module BillingPeriodFilters
    class MatchingAndIgnoredService < BaseService
      INDEX_THRESHOLD = EventMatchingService::INDEX_THRESHOLD

      Result = BaseResult[:matching_filters, :ignored_filters]

      def initialize(target:, filter_index: nil)
        @target = target
        @filter_index = filter_index
        super
      end

      def call
        selected_filter = target.selected_filter
        result.matching_filters = target.filter_values(selected_filter)

        children = child_candidates.find_all do |filter|
          child = target.filter_values(filter)

          result.matching_filters.all? do |key, values|
            values.any? { (child[key] || []).include?(it) }
          end
        end

        result.ignored_filters = children.map do |child_filter|
          child = target.filter_values(child_filter).dup

          if child.keys.sort == result.matching_filters.keys.sort
            if identical_to_matching_filters?(child)
              next unless older_than_filter?(child_filter, selected_filter)
            elsif !subset_of_matching_filters?(child)
              child.each do |key, values|
                next if target.all_filter_values?(selected_filter, key)

                child[key] = values - result.matching_filters[key]
              end
            end
          end

          child
        end.compact

        result
      end

      private

      attr_reader :target, :filter_index

      def child_candidates
        return other_filters unless indexed_matching?

        indexed_child_candidates
      end

      def indexed_matching?
        target.filters.size >= INDEX_THRESHOLD
      end

      def indexed_child_candidates
        candidates = (filter_index || Events::BillingPeriodFilters::FilterIndex.new(target:)).candidates_overlapping_all(result.matching_filters)
        candidates.reject { it.id == target.selected_filter.id }
      end

      def other_filters
        target.filters.reject { it.id == target.selected_filter.id }
      end
    end
  end
end
```

Resolvers can reuse the same cached index object used by `EventMatchingService`:

```ruby
filter_index = filter_index_for(target)

Events::BillingPeriodFilters::EventMatchingService.call(
  target:,
  event:,
  filter_index:
)

Events::BillingPeriodFilters::MatchingAndIgnoredService.call(
  target: target.with_filter(filter),
  filter_index:
)
```

The omitted private helpers stay unchanged:

```ruby
def subset_of_matching_filters?(child)
  child.all? { |key, values| (values - result.matching_filters[key]).empty? }
end

def identical_to_matching_filters?(child)
  child.all? { |key, values| values.sort == result.matching_filters[key].sort }
end

def older_than_filter?(child, selected_filter)
  return true if selected_filter.created_at.nil?

  ([child.created_at, child.id] <=> [selected_filter.created_at, selected_filter.id]).negative?
end
```

#### Affected Classes

- `app/services/events/billing_period_filters/matching_and_ignored_service.rb`
- `app/services/events/billing_period_filters/filter_index.rb`
- `app/services/charge_filters/matching_and_ignored_service.rb` if it remains as a compatibility wrapper

#### Verification

Focused specs:

```bash
lago exec api bundle exec rspec spec/services/events/billing_period_filters/filter_index_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/matching_and_ignored_service_spec.rb
lago exec api bundle exec rspec spec/services/charge_filters/matching_and_ignored_service_spec.rb
```

Key assertions:

- below `INDEX_THRESHOLD`, the service uses the linear scan path.
- at or above `INDEX_THRESHOLD`, the service uses indexed child candidates.
- indexed matching returns the same `matching_filters` and `ignored_filters` as the linear scan.
- candidates include filters that overlap the selected filter on every selected key.
- candidates do not require matching keys that are absent from the selected filter.
- `ChargeFilterValue::ALL_FILTER_VALUES` behavior remains unchanged through `target.all_filter_values?`.
- identical-filter tie-breaking by `[created_at, id]` remains unchanged.

# Feature flag {color="orange_bg"}

- **Flag name:** none for phase 1.
- **What is gated:** phase 2 product-catalog usage depends on the broader product-catalog billing rollout, but the service refactor itself should be backward-compatible.
- **What ships ungated:** phase 1 charge-backed `filter_targets` result and compatibility wrappers.
- **Backward compatibility statement:** existing charge billing should produce the same filter buckets and fees after callers switch from `.charges` to `.filter_targets` and from `charge.id` to `charge.target_key`.

# Work breakdown {color="orange_bg"}

Outcome is a phased implementation plan. Phase 1 and phase 2 should be sequential. Phase 3 and phase 4 can be done after correctness is validated and can be split into separate PRs.

**Group 1: Backend**

- [ ] **T1** — Add `FilterTarget`, `Sources::Charge`, shared matching services, and charge compatibility wrappers.
- [ ] **T2** — Move legacy `Events::BillingPeriodFilterService` orchestration into `ChargesResolver` and return `filter_targets`. *(depends on T1)*
- [ ] **T3** — Update internal charge billing/current-usage callers to read `.filter_targets` with `charge.target_key`. *(depends on T2)*
- [ ] **T4** — Add `BillingCyclesService`, `BillingCyclesResolver`, and `Sources::BillingCycle`. *(depends on T1, T2)*
- [ ] **T5** — Wire product-catalog metered billing/current usage to product-keyed `filter_targets`. *(depends on T4)*
- [ ] **T6** — Add shared `FilterIndex` and optimize `EventMatchingService`. *(depends on T1, T2)*
- [ ] **T7** — Reuse `FilterIndex` in `MatchingAndIgnoredService`. *(depends on T6)*

## Frontend tasks {color="gray_bg"}

No frontend task is expected for this internal service refactor.

- [ ] Sync with frontend only if a later product-catalog current-usage response changes API payloads.

# Release strategy {color="orange_bg"}

- [ ] Merge phase 1 charge-backed refactor as a backward-compatible behavior-preserving change.
- [ ] Merge phase 2 billing-cycle support behind the broader product-catalog billing integration path.
- [ ] Merge phase 3 event-matching optimization after phase 1/2 correctness specs are stable.
- [ ] Merge phase 4 ignored-filter optimization after phase 3 proves the shared `FilterIndex` contract.

## Unlock {color="gray_bg"}

- [ ] Phase 1 specs pass for legacy charge billing and current usage.
- [ ] Phase 2 specs pass for billing-cycle/product-filter targets.
- [ ] Product-catalog metered billing uses product-keyed `filter_targets` in a controlled rollout.
- [ ] Optimization phases show identical results to linear scans in specs.

# Monitoring & alerts {color="orange_bg"}

- Track fee-calculation errors after phase 1 because the runtime result field changes from `.charges` to `.filter_targets`.
- Track product-catalog metered billing errors after phase 2 because product filters start using the shared matcher.
- Consider adding temporary logs around unexpectedly empty `filter_targets` for product-catalog billing cycles during rollout.
- No new Grafana or Metabase dashboard is required unless rollout metrics show regressions.

# QA plan {color="orange_bg"}

Concrete scenarios:

- Happy path: existing charge with no filters still records the default `nil` bucket under `charge.target_key`.
- Happy path: existing charge with matching charge filters records the same filter ids as before.
- Happy path: recurring charge seeding still carries previous-period usage.
- Edge case: pre-enriched charge events still use `charge_id` / `charge_filter_id` input but record prefixed charge target keys.
- Edge case: product-catalog billing cycle with product filters records buckets under `product.target_key`.
- Edge case: product-catalog billing cycle never uses `billing_cycle.id` as the event-filter key.
- Edge case: `ChargeFilterValue::ALL_FILTER_VALUES` behavior remains unchanged for charge-backed ignored filters.
- Optimization: indexed event matching returns the same matching filters and selected filter as linear matching.
- Optimization: indexed ignored-filter matching returns the same matching and ignored filters as linear matching.

Focused specs for phase 1:

```bash
lago exec api bundle exec rspec spec/services/events/billing_period_filter_service_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/filter_target_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/event_matching_service_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/matching_and_ignored_service_spec.rb
lago exec api bundle exec rspec spec/services/charge_filters/event_matching_service_spec.rb
lago exec api bundle exec rspec spec/services/charge_filters/matching_and_ignored_service_spec.rb
```

Focused specs for phase 2:

```bash
lago exec api bundle exec rspec spec/services/events/billing_period_filters/billing_cycles_service_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/billing_cycles_resolver_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/sources/billing_cycle_spec.rb
```

Focused specs for phase 3:

```bash
lago exec api bundle exec rspec spec/services/events/billing_period_filters/filter_index_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/event_matching_service_spec.rb
```

Focused specs for phase 4:

```bash
lago exec api bundle exec rspec spec/services/events/billing_period_filters/filter_index_spec.rb
lago exec api bundle exec rspec spec/services/events/billing_period_filters/matching_and_ignored_service_spec.rb
lago exec api bundle exec rspec spec/services/charge_filters/matching_and_ignored_service_spec.rb
```

Key assertions:

- `Events::BillingPeriodFilterService` returns `filter_targets` with the legacy charge-keyed shape.
- Charge-backed target keys use `Charge#target_key`.
- `Events::BillingPeriodFilters::BillingCyclesService` returns `filter_targets` with the product-keyed shape.
- Billing-cycle-backed target keys use `Product#target_key`.
- Billing-cycle filtering uses `contract_rate_card.product` and product filters.
- Billing-cycle filtering uses `distinct_codes_and_property_combinations`, not `distinct_charges_and_filters`.
- In-memory current-usage cycles are keyed through `Events::BillingPeriodFilters::FilterTarget#target_key`.
- Filter target matching preserves charge-filter behavior and supports product filters without product-specific matcher classes.
- `target_key` is not used for fee persistence, idempotency, invoiceable ids, or billing-cycle identity.

# Appendix {color="orange_bg"}

## Why FilterTarget Instead Of MeteredItem {color="gray_bg"}

`Fees::ChargeService::MeteredItem` is a fee-calculation abstraction. It carries pricing, boundaries, invoiceability, grouping, and aggregation options.

`Events::BillingPeriodFilters::FilterTarget` is smaller and belongs only to event prefiltering. It exposes event matching dependencies:

- billable metric
- available filters
- selected filter
- filter hash values
- filter specificity
- all-values handling
- event-filter target key

Keeping the POROs separate avoids coupling event prefiltering to fee-calculation behavior and avoids requiring fake billing boundaries for filter-only work.

## Why FilterTarget Instead Of ProductFilters Services {color="gray_bg"}

Separate `ProductFilters::EventMatchingService` and `ProductFilters::MatchingAndIgnoredService` classes would duplicate the charge-filter algorithms with product-specific names.

The algorithm is shared. The source of filter data changes. `FilterTarget` makes that source-specific data available through one contract, so the services stay generic.

## Production data analysis {color="gray_bg"}

The production filter-count sample is summarized in the phase 3 optimization section. The raw source file is `tmp/query_result_2026-08-28T14_04_27.825319051Z.json`.

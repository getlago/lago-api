# frozen_string_literal: true

module V2
  class EventsQuery < BaseQuery
    Result = BaseResult[:events]
    Filters = BaseFilters[
      :code, :transaction_id, :external_contract_id, :timestamp_from_started_at, :timestamp_from, :timestamp_to
    ]

    def self.event_model(organization:)
      if organization.postgres_events_store?
        Event
      else
        Clickhouse::ProductEventsEnriched
      end
    end

    def self.cursor_sort(organization:)
      return CursorPagination::DEFAULT_SORT if organization.postgres_events_store?

      {timestamp: :desc, external_contract_id: :desc, code: :desc, transaction_id: :desc}
    end

    def call
      return result unless validate_filters.success?

      events = event_model.where(organization_id: organization.id)
      # Reprocessing creates new versions; FINAL returns the latest version before paging.
      events = events.from("#{event_model.quoted_table_name} FINAL") unless organization.postgres_events_store?
      events = events.where(transaction_id: filters.transaction_id) if filters.transaction_id.present?
      events = events.where(code: filters.code) if filters.code.present?
      events = events.where(contract_column => filters.external_contract_id) if filters.external_contract_id.present?
      events = with_timestamp_range(events)
      events = events.order(self.class.cursor_sort(organization:))

      result.events = paginate(events)
      result
    rescue BaseService::FailedResult
      result
    end

    private

    def filters_contract
      @filters_contract ||= Queries::V2::EventsQueryFiltersContract.new
    end

    def event_model
      self.class.event_model(organization:)
    end

    def contract_column
      organization.postgres_events_store? ? :external_subscription_id : :external_contract_id
    end

    def with_timestamp_range(scope)
      if ActiveModel::Type::Boolean.new.cast(filters.timestamp_from_started_at)
        contract = organization.contracts.order(Arel.sql("terminated_at DESC NULLS FIRST"), started_at: :desc, created_at: :desc)
          .find_by(external_id: filters.external_contract_id)
        scope = scope.where(timestamp: contract.started_at..) if contract&.started_at
      elsif filters.timestamp_from.present?
        scope = scope.where(timestamp: parse_datetime_filter(:timestamp_from)..)
      end

      scope = scope.where(timestamp: ..parse_datetime_filter(:timestamp_to)) if filters.timestamp_to.present?
      scope
    end
  end
end

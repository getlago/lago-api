# frozen_string_literal: true

# Declares calculation values (sums, counts, ...) that can be preloaded for a
# batch of records with a single grouped query, caching the result on each
# record to avoid N+1 queries during serialization.
#
# A value is declared with `preloadable_aggregation`, which generates a reader
# method. The reader returns the cached value when it was preloaded, and falls
# back to running the query for the single record otherwise:
#
#   class Invoice < ApplicationRecord
#     include PreloadableAggregations
#
#     preloadable_aggregation :offset_amount_cents do |ids|
#       CreditNote.where(invoice_id: ids).finalized.group(:invoice_id).sum(:offset_amount_cents)
#     end
#   end
#
# The block receives the ids of the batch and must return a `{id => value}`
# hash. An aggregation cached on an associated model is declared with
# `preloadable_associated_aggregation`, which cascades the preload to the
# association (loading it first when it is not already loaded):
#
#   preloadable_associated_aggregation :fees, :credited_amount_cents
#
# Preloading is triggered with the class method. Passing no names preloads
# every declared aggregation (own and associated); passing names limits it to
# those own aggregations and the associations named:
#
#   Invoice.preload_aggregations(invoices)
#   Invoice.preload_aggregations(invoices, :offset_amount_cents)
module PreloadableAggregations
  extend ActiveSupport::Concern

  included do
    # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    # Only written at class-load time by the macros below, never at runtime.
    class_attribute :own_aggregations, instance_accessor: false, default: {}
    class_attribute :associated_aggregations, instance_accessor: false, default: {}
    # rubocop:enable ThreadSafety/ClassAndModuleAttributes
  end

  class_methods do
    def preloadable_aggregation(name, default: 0, &batch)
      name = name.to_sym
      self.own_aggregations = own_aggregations.merge(name => {batch:, default:})

      define_method(name) do
        return aggregation_cache[name] if aggregation_cache.key?(name)

        # Not preloaded: compute live on every call and do NOT cache. The rows
        # this sums over can change between calls during create/validate flows,
        # so a cached fallback would go stale. Only an explicit
        # preload_aggregations (index paths) caches.
        definition = self.class.own_aggregations.fetch(name)
        next definition[:default] if id.nil?

        definition[:batch].call([id]).fetch(id, definition[:default])
      end
    end

    def preloadable_associated_aggregation(association, *names)
      association = association.to_sym
      merged = (associated_aggregations[association].to_a + names.map(&:to_sym)).uniq
      self.associated_aggregations = associated_aggregations.merge(association => merged)
    end

    def preload_aggregations(records, *names)
      # Array() loads a relation and returns its own cached instances, so the
      # values cached below are the ones the returned relation yields later.
      collection = Array(records)
      return records if collection.empty?

      names = names.map(&:to_sym)
      own = names.empty? ? own_aggregations.keys : names & own_aggregations.keys
      associated = names.empty? ? associated_aggregations : associated_aggregations.slice(*names)

      preload_own_aggregations(collection, own)
      preload_associated_aggregations(collection, associated)

      records
    end

    private

    def preload_own_aggregations(records, names)
      return if names.empty?

      ids = records.map(&:id).compact

      names.each do |name|
        definition = own_aggregations.fetch(name)
        # Records without an id (e.g. a non-persisted preview invoice) get the
        # default without querying, matching the pre-preload behaviour of an
        # empty association.
        values = ids.empty? ? {} : definition[:batch].call(ids)
        records.each { |record| record.aggregation_cache[name] = values.fetch(record.id, definition[:default]) }
      end
    end

    def preload_associated_aggregations(records, associations)
      associations.each do |association, names|
        next if names.empty?

        unloaded = records.reject { |record| record.association(association).loaded? }
        ActiveRecord::Associations::Preloader.new(records: unloaded, associations: association).call if unloaded.any?

        targets = records.flat_map { |record| Array(record.public_send(association)) }.uniq
        next if targets.empty?

        targets.group_by(&:class).each do |klass, klass_targets|
          klass.preload_aggregations(klass_targets, *names)
        end
      end
    end
  end

  def aggregation_cache
    @aggregation_cache ||= {}
  end
end

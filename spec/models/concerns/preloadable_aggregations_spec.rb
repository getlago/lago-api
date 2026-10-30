# frozen_string_literal: true

require "rails_helper"

# Exercised through Invoice and Fee, which declare both an own aggregation
# (offset/refunded amounts) and an associated one (fees' credited amount).
RSpec.describe PreloadableAggregations do
  let(:invoice) { create(:invoice) }

  def count_queries
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless /\A\s*(SAVEPOINT|RELEASE|BEGIN|COMMIT|ROLLBACK)/i.match?(payload[:sql])
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  before do
    create(:credit_note, invoice:, offset_amount_cents: 5_00, refund_amount_cents: 5_00)
    create(:credit_note, invoice:, offset_amount_cents: 10_00, refund_amount_cents: 10_00)
    create(:credit_note, invoice:, offset_amount_cents: 20_00, refund_amount_cents: 20_00, status: :draft)

    credit_note = create(:credit_note, invoice:)
    fee1 = create(:fee, invoice:)
    fee2 = create(:fee, invoice:)

    create(:credit_note_item, credit_note:, fee: fee1, amount_cents: 5_00)
    create(:credit_note_item, credit_note:, fee: fee2, amount_cents: 10_00)
    create(:credit_note_item, credit_note:, fee: fee2, amount_cents: 15_00)
  end

  describe ".preload_aggregations" do
    context "when no names are passed" do
      it "caches every own and associated aggregation" do
        Invoice.preload_aggregations([invoice])

        expect(invoice.aggregation_cache).to eq(
          offset_amount_cents: 15_00,
          refunded_amount_cents: 35_00,
          has_non_voided_credit_notes?: true
        )
        expect(invoice.fees.first.aggregation_cache).to eq(credited_amount_cents: 5_00)
        expect(invoice.fees.last.aggregation_cache).to eq(credited_amount_cents: 25_00)
      end

      it "reads the cached values without extra queries" do
        Invoice.preload_aggregations([invoice])

        queries = count_queries do
          expect(invoice.offset_amount_cents).to eq(15_00)
          expect(invoice.refunded_amount_cents).to eq(35_00)
          expect(invoice.fees.map(&:credited_amount_cents)).to eq([5_00, 25_00])
        end

        expect(queries).to eq(0)
      end
    end

    context "when specific names are passed" do
      it "caches only the named own aggregation" do
        Invoice.preload_aggregations([invoice], :offset_amount_cents)

        expect(invoice.aggregation_cache).to eq(offset_amount_cents: 15_00)
        expect(invoice.fees.map(&:aggregation_cache)).to all(eq({}))
      end

      it "caches only the named association when an association name is passed" do
        Invoice.preload_aggregations([invoice], :fees)

        expect(invoice.aggregation_cache).to eq({})
        expect(invoice.fees.first.aggregation_cache).to eq(credited_amount_cents: 5_00)
      end
    end

    context "with several records" do
      let(:other_invoice) { create(:invoice) }

      before do
        create(:credit_note, invoice: other_invoice, status: :finalized, offset_amount_cents: 7_00)
      end

      it "caches the right value on each record" do
        Invoice.preload_aggregations([invoice, other_invoice], :offset_amount_cents)

        expect(invoice.aggregation_cache[:offset_amount_cents]).to eq(15_00)
        expect(other_invoice.aggregation_cache[:offset_amount_cents]).to eq(7_00)
      end

      it "runs a constant number of queries regardless of the record count" do
        third = create(:invoice)
        # Fresh instances each time so one call does not warm the next one's cache.
        queries_for = ->(ids) { count_queries { Invoice.preload_aggregations(Invoice.where(id: ids).to_a) } }

        one = queries_for.call([invoice.id])
        many = queries_for.call([invoice.id, other_invoice.id, third.id])

        expect(many).to eq(one)
      end
    end

    context "when the associated records are not loaded" do
      let(:other_invoice) { create(:invoice) }

      before { create(:fee, invoice: other_invoice) }

      it "loads the association for every record in a single query" do
        records = Invoice.where(id: [invoice.id, other_invoice.id]).to_a # :fees not loaded

        fees_queries = 0
        counter = ->(_n, _s, _f, _i, payload) { fees_queries += 1 if payload[:sql].include?('FROM "fees"') }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          Invoice.preload_aggregations(records)
        end

        # Without the preloader, flat_map(&:fees) would lazy-load one query per record.
        expect(fees_queries).to eq(1)
        expect(records).to all(satisfy { |r| r.association(:fees).loaded? })
      end
    end

    context "when the records are empty" do
      it "does not run any query" do
        expect(count_queries { Invoice.preload_aggregations([]) }).to eq(0)
      end
    end
  end

  describe "the default option" do
    let(:model) do
      Class.new(Invoice) do
        preloadable_aggregation :never_found, default: -1 do |_ids|
          {} # no row matches, so every record falls back to the default
        end
      end
    end

    it "returns the configured default when no value is found" do
      expect(model.new.never_found).to eq(-1)

      model.preload_aggregations([invoice])
      expect(invoice.aggregation_cache[:never_found]).to eq(-1)
    end
  end

  describe "generated reader" do
    context "when the value was not preloaded" do
      it "computes it live without caching" do
        expect(invoice.offset_amount_cents).to eq(15_00)
        expect(invoice.aggregation_cache).not_to have_key(:offset_amount_cents)
      end

      it "reflects changes between calls instead of serving a stale cache" do
        expect(invoice.offset_amount_cents).to eq(15_00)

        create(:credit_note, invoice:, status: :finalized, offset_amount_cents: 5_00)

        expect(invoice.offset_amount_cents).to eq(20_00)
      end
    end

    context "when the record is not persisted" do
      it "returns the default without querying" do
        new_invoice = Invoice.new

        queries = count_queries { expect(new_invoice.offset_amount_cents).to eq(0) }

        expect(queries).to eq(0)
      end
    end

    context "when the preloaded value is zero" do
      it "returns the cached zero without falling back" do
        invoice.aggregation_cache[:offset_amount_cents] = 0

        queries = count_queries { expect(invoice.offset_amount_cents).to eq(0) }

        expect(queries).to eq(0)
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationThrottleKey do
  let(:quickbooks_type) { "Integrations::QuickbooksIntegration" }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:credit_note) { create(:credit_note, customer:, invoice:) }
  let(:payment) { create(:payment, payable: invoice) }

  # A QuickBooks row is a NetSuite row whose type is rewritten: the type has no model yet,
  # so the row is never loaded again and only its id is used.
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_id) { integration.id }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
  let(:integration_gid) { "gid://#{GlobalID.app}/#{quickbooks_type}/#{integration_id}" }

  let(:invoice_args) { Integrations::Aggregator::Invoices::CreateJob.new(invoice:).serialize["arguments"] }
  let(:credit_note_args) { Integrations::Aggregator::CreditNotes::CreateJob.new(credit_note:).serialize["arguments"] }
  let(:payment_args) { Integrations::Aggregator::Payments::CreateJob.new(payment:).serialize["arguments"] }
  let(:create_customer_args) do
    [{
      "integration_customer_params" => {"sync_with_provider" => true, "_aj_symbol_keys" => %w[sync_with_provider]},
      "integration" => {"_aj_globalid" => integration_gid},
      "customer" => {"_aj_globalid" => customer.to_gid.to_s},
      "_aj_ruby2_keywords" => %w[integration_customer_params integration customer]
    }]
  end
  let(:update_customer_args) do
    [{
      "integration_customer_params" => {"sync_with_provider" => true, "_aj_symbol_keys" => %w[sync_with_provider]},
      "integration" => {"_aj_globalid" => integration_gid},
      "integration_customer" => {"_aj_globalid" => integration_customer.to_gid.to_s},
      "_aj_ruby2_keywords" => %w[integration_customer_params integration integration_customer]
    }]
  end

  let(:record_shapes) { %i[invoice_args credit_note_args payment_args] }
  let(:integration_shapes) { %i[create_customer_args update_customer_args] }
  let(:quickbooks_suffix) { Digest::SHA256.hexdigest(integration_id) }

  def resolve(args)
    [described_class.limit(*args), described_class.key_suffix(*args)]
  end

  context "when the customer is connected to a QuickBooks integration" do
    before do
      integration_customer
      integration.update_column(:type, quickbooks_type) # rubocop:disable Rails/SkipsModelValidations
    end

    it "returns the limit and a digest of the integration id for the jobs of a record" do
      record_shapes.each do |shape|
        expect(resolve(public_send(shape))).to eq([3, quickbooks_suffix]), shape.to_s
      end

      expect(quickbooks_suffix).to match(/\A\h{64}\z/)
      expect(quickbooks_suffix).not_to include(integration_id)
    end

    it "returns the limit and the same digest for the integration customer jobs without a query" do
      integration_shapes.each do |shape|
        args = public_send(shape)
        resolved = nil

        expect(capture_sql { resolved = resolve(args) }).to be_empty, shape.to_s
        expect(resolved).to eq([3, quickbooks_suffix]), shape.to_s
      end
    end

    it "reads the payload with symbol keys too" do
      expect(resolve([{invoice: {_aj_globalid: invoice.to_gid.to_s}}])).to eq([3, quickbooks_suffix])
    end

    it "computes the same suffix again from the database when nothing is cached" do
      first = described_class.key_suffix(*invoice_args)
      statements = capture_sql { expect(described_class.key_suffix(*invoice_args)).to eq(first) }

      expect(first).to eq(quickbooks_suffix)
      expect(statements).not_to be_empty
    end

    context "with a second QuickBooks connection" do
      let(:other_customer) { create(:customer, organization:) }
      let(:other_integration) { create(:netsuite_integration, organization:) }
      let(:other_invoice) { create(:invoice, customer: other_customer, organization:) }
      let(:other_args) { Integrations::Aggregator::Invoices::CreateJob.new(invoice: other_invoice).serialize["arguments"] }

      before do
        create(:netsuite_customer, integration: other_integration, customer: other_customer)
        other_integration.update_column(:type, quickbooks_type) # rubocop:disable Rails/SkipsModelValidations
      end

      it "returns one suffix per connection" do
        expect(described_class.key_suffix(*other_args)).to eq(Digest::SHA256.hexdigest(other_integration.id))
        expect(described_class.key_suffix(*other_args)).not_to eq(described_class.key_suffix(*invoice_args))
      end
    end

    context "when the record is of a class outside the allow-list" do
      let(:subscription) { create(:subscription, customer:) }
      let(:args) { [{"invoice" => {"_aj_globalid" => subscription.to_gid.to_s}}] }

      it "returns no limit and runs no query" do
        args
        resolved = nil

        expect(capture_sql { resolved = resolve(args) }).to be_empty
        expect(resolved).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
      end
    end

    context "when the database raises" do
      before { allow(Invoice).to receive(:unscoped).and_raise(ActiveRecord::StatementInvalid) }

      it "returns no limit and the constant suffix" do
        expect(resolve(invoice_args)).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
      end
    end

    context "when the cache raises" do
      before { allow(Rails.cache).to receive(:fetch).and_raise(StandardError) }

      it "returns no limit and the constant suffix" do
        expect(resolve(invoice_args)).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
      end
    end

    context "with a cache store", cache: :memory do
      it "resolves the same record again without a query" do
        first = resolve(invoice_args)
        second = nil

        expect(capture_sql { second = resolve(invoice_args) }).to be_empty
        expect(second).to eq(first)
        expect(first).to eq([3, quickbooks_suffix])
      end

      it "reads the database again once the entry expired" do
        resolve(invoice_args)

        travel_to(described_class::CACHE_TTL.from_now + 1.second) do
          expect(capture_sql { expect(resolve(invoice_args)).to eq([3, quickbooks_suffix]) }).not_to be_empty
        end
      end
    end
  end

  %i[netsuite xero hubspot anrok avalara].each do |provider|
    context "when the customer is connected to a #{provider} integration" do
      let(:integration) { create(:"#{provider}_integration", organization:) }
      let(:integration_customer) { create(:"#{provider}_customer", integration:, customer:) }
      let(:integration_gid) { integration.to_gid.to_s }

      before { integration_customer }

      it "returns no limit and the constant suffix for the five jobs" do
        (record_shapes + integration_shapes).each do |shape|
          expect(resolve(public_send(shape))).to eq([nil, described_class::NO_CONNECTION_SUFFIX]), shape.to_s
        end
      end
    end
  end

  context "when the customer has no integration customer" do
    it "returns no limit and the constant suffix" do
      record_shapes.each do |shape|
        expect(resolve(public_send(shape))).to eq([nil, described_class::NO_CONNECTION_SUFFIX]), shape.to_s
      end
    end

    context "with a cache store", cache: :memory do
      it "caches the negative result" do
        first = resolve(invoice_args)
        second = nil

        expect(capture_sql { second = resolve(invoice_args) }).to be_empty
        expect(second).to eq(first)
        expect(first).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
      end
    end
  end

  context "when the record does not exist" do
    let(:args) { [{"invoice" => {"_aj_globalid" => "gid://#{GlobalID.app}/Invoice/#{SecureRandom.uuid}"}}] }

    it "returns no limit and does not look for an integration customer" do
      statements = capture_sql { expect(described_class.limit(*args)).to be_nil }

      expect(statements.grep(/FROM "invoices"/).size).to eq(1)
      expect(statements.grep(/integration_customers/)).to be_empty
      expect(described_class.key_suffix(*args)).to eq(described_class::NO_CONNECTION_SUFFIX)
    end
  end

  context "when the arguments are not those of an integration job" do
    let(:malformed) do
      {
        "no argument" => [],
        "nil" => [nil],
        "a string" => ["invoice"],
        "an empty hash" => [{}],
        "a record entry that is not a hash" => [{"invoice" => 12}],
        "a missing global id" => [{"invoice" => {}}],
        "a malformed global id" => [{"invoice" => {"_aj_globalid" => "not-a-gid"}}],
        "a malformed integration global id" => [{"integration" => {"_aj_globalid" => "not-a-gid"}}],
        "an integration entry that is nil" => [{"integration" => nil}]
      }
    end

    it "returns no limit and the constant suffix without raising" do
      malformed.each do |name, args|
        expect(resolve(args)).to eq([nil, described_class::NO_CONNECTION_SUFFIX]), name
      end
    end
  end
end

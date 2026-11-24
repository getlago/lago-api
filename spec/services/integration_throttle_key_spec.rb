# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationThrottleKey do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:credit_note) { create(:credit_note, customer:, invoice:) }
  let(:payment) { create(:payment, payable: invoice) }

  let(:realm_id) { "1111111111" }
  let(:integration) { quickbooks_integration(realm_id:) }
  let(:link_ids) { [SecureRandom.uuid, SecureRandom.uuid].sort }
  let(:integration_customer) { create(:quickbooks_customer, id: link_ids.first, integration:, customer:) }
  let(:integration_gid) { integration.to_gid.to_s }

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
  let(:quickbooks_suffix) { Digest::SHA256.hexdigest("quickbooks:#{realm_id}") }

  def quickbooks_integration(realm_id:, sandbox: false, organization: self.organization, **attributes)
    create(
      :quickbooks_integration,
      organization:,
      code: "quickbooks_#{SecureRandom.hex(4)}",
      settings: {realm_id:, sandbox:, sync_invoices: false, sync_credit_notes: false, sync_payments: false},
      **attributes
    )
  end

  def resolve(args)
    [described_class.limit(*args), described_class.key_suffix(*args)]
  end

  # The resolution of the last limit stays on the thread: each example starts without one.
  before { Thread.current[described_class::THREAD_KEY] = nil }

  describe ".limit and .key_suffix" do
    subject(:resolved) { resolve(args) }

    let(:args) { invoice_args }

    context "when the customer is connected to a QuickBooks integration" do
      before { integration_customer }

      it "returns the limit and a digest of the QuickBooks company for the jobs of a record" do
        record_shapes.each do |shape|
          expect(resolve(public_send(shape))).to eq([3, quickbooks_suffix]), shape.to_s
        end

        expect(quickbooks_suffix).to match(/\A\h{64}\z/)
        expect(quickbooks_suffix).not_to include(realm_id)
      end

      # Pinned to the null store: an earlier `cache: :memory` example leaves its store in Rails.cache.
      it "returns the limit and the same digest for the integration customer jobs, reading only the integration", cache: :null do
        integration_shapes.each do |shape|
          args = public_send(shape)
          resolved = nil

          statements = capture_sql { resolved = resolve(args) }
          expect(statements).not_to be_empty, shape.to_s
          expect(statements).to all(include('FROM "integrations"')), shape.to_s
          expect(resolved).to eq([3, quickbooks_suffix]), shape.to_s
        end
      end

      context "with a sandbox company" do
        let(:integration) { quickbooks_integration(realm_id:, sandbox: true) }

        it "returns a digest of the sandbox company, apart from the production one" do
          expect(resolve(invoice_args)).to eq([3, Digest::SHA256.hexdigest("quickbooks-sandbox:#{realm_id}")])
        end
      end

      context "when the integration has no company id" do
        let(:integration) { quickbooks_integration(realm_id: nil) }

        it "returns a digest of the integration id" do
          expect(resolve(invoice_args)).to eq([3, Digest::SHA256.hexdigest(integration.id)])
        end
      end

      context "with symbol keys in the payload" do
        let(:args) { [{invoice: {_aj_globalid: invoice.to_gid.to_s}}] }

        it "returns the limit and the digest" do
          expect(resolved).to eq([3, quickbooks_suffix])
        end
      end

      context "when the customer is also linked to a NetSuite integration" do
        let(:netsuite_integration) { create(:netsuite_integration, organization:) }

        context "when the NetSuite link comes first, so the record jobs sync to NetSuite" do
          let(:integration_customer) { create(:quickbooks_customer, id: link_ids.last, integration:, customer:) }

          before { create(:netsuite_customer, id: link_ids.first, integration: netsuite_integration, customer:) }

          it "returns no limit for the jobs of a record" do
            record_shapes.each do |shape|
              expect(resolve(public_send(shape))).to eq([nil, described_class::NO_CONNECTION_SUFFIX]), shape.to_s
            end
          end
        end

        context "when the QuickBooks link comes first, so the record jobs sync to QuickBooks" do
          before { create(:netsuite_customer, id: link_ids.last, integration: netsuite_integration, customer:) }

          it "returns the limit and the QuickBooks company digest" do
            expected = Digest::SHA256.hexdigest("quickbooks:#{realm_id}")

            record_shapes.each do |shape|
              expect(resolve(public_send(shape))).to eq([3, expected]), shape.to_s
            end
          end
        end
      end

      context "when the resolution fails after the limit was returned" do
        before do
          calls = 0
          allow(Rails.cache).to receive(:fetch).and_wrap_original do |original, *fetch_args, **options, &block|
            calls += 1
            raise StandardError if calls > 1

            original.call(*fetch_args, **options, &block)
          end
        end

        it "returns the suffix of the resolution that gave the limit" do
          expect(resolved).to eq([3, quickbooks_suffix])
        end

        it "returns the constant suffix for other arguments" do
          described_class.limit(*invoice_args)

          expect(described_class.key_suffix(*credit_note_args)).to eq(described_class::NO_CONNECTION_SUFFIX)
        end
      end

      # Pinned to the null store: an earlier `cache: :memory` example leaves its store in Rails.cache.
      it "computes the same suffix again from the database when nothing is cached", cache: :null do
        first = described_class.key_suffix(*invoice_args)
        statements = capture_sql { expect(described_class.key_suffix(*invoice_args)).to eq(first) }

        expect(first).to eq(quickbooks_suffix)
        expect(statements).not_to be_empty
      end

      context "with another QuickBooks integration" do
        let(:other_organization) { create(:organization) }
        let(:other_customer) { create(:customer, organization: other_organization) }
        let(:other_invoice) { create(:invoice, customer: other_customer, organization: other_organization) }
        let(:other_args) { Integrations::Aggregator::Invoices::CreateJob.new(invoice: other_invoice).serialize["arguments"] }

        before do
          create(:quickbooks_customer, integration: other_integration, customer: other_customer)
        end

        context "when it is connected to another company" do
          let(:other_integration) { quickbooks_integration(realm_id: "2222222222", organization: other_organization) }

          it "returns one suffix per company" do
            expect(described_class.key_suffix(*other_args)).to eq(Digest::SHA256.hexdigest("quickbooks:2222222222"))
            expect(described_class.key_suffix(*other_args)).not_to eq(described_class.key_suffix(*invoice_args))
          end
        end

        context "when it is connected to the same company from another organization" do
          let(:other_integration) { quickbooks_integration(realm_id:, organization: other_organization) }

          it "returns the same suffix, so both share the company's slots" do
            expect(described_class.key_suffix(*other_args)).to eq(described_class.key_suffix(*invoice_args))
          end
        end
      end

      context "when the payload holds an integration entry and a record entry" do
        let(:unlinked_customer) { create(:customer, organization:) }
        let(:unlinked_invoice) { create(:invoice, customer: unlinked_customer, organization:) }
        let(:args) do
          [{
            "invoice" => {"_aj_globalid" => unlinked_invoice.to_gid.to_s},
            "integration" => {"_aj_globalid" => integration_gid}
          }]
        end

        it "resolves from the integration entry without looking up the record" do
          args

          expect(capture_sql { resolved }).to all(include('FROM "integrations"'))
          expect(resolved).to eq([3, quickbooks_suffix])
        end
      end

      context "when the payload holds several record entries" do
        let(:unlinked_customer) { create(:customer, organization:) }
        let(:unlinked_invoice) { create(:invoice, customer: unlinked_customer, organization:) }
        let(:unlinked_credit_note) { create(:credit_note, customer: unlinked_customer, invoice: unlinked_invoice) }
        let(:linked) { {"_aj_globalid" => invoice.to_gid.to_s} }
        let(:linked_credit_note) { {"_aj_globalid" => credit_note.to_gid.to_s} }
        let(:linked_payment) { {"_aj_globalid" => payment.to_gid.to_s} }
        let(:unlinked) { {"_aj_globalid" => unlinked_invoice.to_gid.to_s} }
        let(:unlinked_credit_note_entry) { {"_aj_globalid" => unlinked_credit_note.to_gid.to_s} }

        it "resolves from the invoice first, then the credit note, then the payment" do
          expect(resolve([{"payment" => linked_payment, "credit_note" => unlinked_credit_note_entry, "invoice" => linked}]))
            .to eq([3, quickbooks_suffix])
          expect(resolve([{"payment" => linked_payment, "credit_note" => linked_credit_note, "invoice" => unlinked}]))
            .to eq([nil, described_class::NO_CONNECTION_SUFFIX])
          expect(resolve([{"payment" => linked_payment, "credit_note" => unlinked_credit_note_entry}]))
            .to eq([nil, described_class::NO_CONNECTION_SUFFIX])
          expect(resolve([{"payment" => unlinked, "credit_note" => linked_credit_note}]))
            .to eq([3, quickbooks_suffix])
        end
      end

      context "when the record is of a class outside the allow-list" do
        let(:subscription) { create(:subscription, customer:) }
        let(:args) { [{"invoice" => {"_aj_globalid" => subscription.to_gid.to_s}}] }

        it "returns no limit and runs no query" do
          args

          expect(capture_sql { resolved }).to be_empty
          expect(resolved).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
        end
      end

      context "when the database raises" do
        before { allow(Invoice).to receive(:unscoped).and_raise(ActiveRecord::StatementInvalid) }

        it "returns no limit and the constant suffix" do
          expect(resolved).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
        end

        it "logs one warning without ids and still returns no limit and the constant suffix" do
          allow(Rails.logger).to receive(:warn)

          expect(resolved).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
          expect(Rails.logger).to have_received(:warn)
            .with("IntegrationThrottleKey fail open: ActiveRecord::StatementInvalid").once
        end

        it "returns no limit and the constant suffix when the logger raises" do
          allow(Rails.logger).to receive(:warn).and_raise(StandardError)

          expect(resolved).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
        end
      end

      context "when the cache raises" do
        before { allow(Rails.cache).to receive(:fetch).and_raise(StandardError) }

        it "returns no limit and the constant suffix" do
          expect(resolved).to eq([nil, described_class::NO_CONNECTION_SUFFIX])
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

      it "returns no limit and the constant suffix without raising or logging" do
        allow(Rails.logger).to receive(:warn)

        malformed.each do |name, args|
          expect(resolve(args)).to eq([nil, described_class::NO_CONNECTION_SUFFIX]), name
        end

        expect(Rails.logger).not_to have_received(:warn)
      end
    end
  end
end

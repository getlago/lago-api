# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Throttling initializer" do # rubocop:disable RSpec/DescribeClass
  def limits_for(provider)
    Throttling.limits[provider].to_hash.deep_symbolize_keys
  end

  it "registers exactly the six provider entries" do
    expect(Throttling.limits.keys).to match_array(%w[hubspot xero netsuite anrok avalara quickbooks])
  end

  it "keeps the existing provider limits unchanged" do
    expect(limits_for(:hubspot)).to eq(tensecondly: {limit: 110, period: 10})
    expect(limits_for(:xero)).to eq(minutely: {limit: 60, period: 60}, daily: {limit: 5000, period: 86400})
    expect(limits_for(:netsuite)).to eq(secondly: {limit: 10, period: 1})
    expect(limits_for(:anrok)).to eq(secondly: {limit: 9, period: 1})
    expect(limits_for(:avalara)).to eq(secondly: {limit: 10, period: 1})
  end

  it "limits QuickBooks to a single window of 150 per 60 seconds" do
    expect(limits_for(:quickbooks)).to eq(minutely: {limit: 150, period: 60})
  end

  context "with a real counter store" do
    let(:check_value) { "placeholder-throttle-key" }

    before do
      allow(Throttling).to receive(:storage).and_return(ActiveSupport::Cache::MemoryStore.new)
      travel_to(Time.zone.parse("2026-01-05 10:00:00"))
    end

    def check_quickbooks
      Throttling.for(:quickbooks).check(:client, check_value)
    end

    it "allows 150 QuickBooks calls in one minute and refuses the 151st" do
      results = Array.new(150) { check_quickbooks }

      expect(results).to all(be(true))
      expect(check_quickbooks).to be(false)
    end

    it "still refuses QuickBooks calls 59 seconds into the same minute" do
      151.times { check_quickbooks }

      travel(59.seconds)

      expect(check_quickbooks).to be(false)
    end

    it "allows QuickBooks calls again in the next minute" do
      151.times { check_quickbooks }

      travel(60.seconds)

      expect(check_quickbooks).to be(true)
    end
  end

  describe "shared concurrency limit and the QuickBooks per-company rule" do
    let(:strategy) { Sidekiq::Throttled::Registry.get(:concurrency_limit) }
    let(:shared_key) { "throttled:concurrency_limit:concurrency.v2" }
    let(:organization) { create(:organization) }

    # The QuickBooks customer link has no model yet: a NetSuite link whose type is rewritten
    # stands in for it, outside accounting_kind.
    let(:quickbooks_customer_type) { "IntegrationCustomers::QuickbooksCustomer" }
    let(:integration_a) { create(:quickbooks_integration, organization:, code: "quickbooks_a", settings: {realm_id: "1111111111"}) }
    let(:integration_b) { create(:quickbooks_integration, organization:, code: "quickbooks_b", settings: {realm_id: "2222222222"}) }
    let(:customer_a) { create(:customer, organization:) }
    let(:customer_b) { create(:customer, organization:) }
    let(:args_a) { invoice_job_args(customer_a) }
    let(:args_b) { invoice_job_args(customer_b) }
    let(:key_a) { company_key(integration_a) }
    let(:key_b) { company_key(integration_b) }

    def invoice_job_args(customer)
      invoice = create(:invoice, customer:, organization:)
      Integrations::Aggregator::Invoices::CreateJob.new(invoice:).serialize["arguments"]
    end

    def company_key(integration)
      "#{shared_key}:#{Digest::SHA256.hexdigest("quickbooks:#{integration.realm_id}")}"
    end

    def throttle_keys
      Sidekiq.redis { |conn| conn.call("KEYS", "throttled:concurrency_limit:*") }
    end

    def clear_throttle_keys
      keys = throttle_keys
      Sidekiq.redis { |conn| conn.call("DEL", *keys) } if keys.any?
    end

    def jids_in(key)
      Sidekiq.redis { |conn| conn.call("ZRANGE", key, 0, -1) }
    end

    # Fetches `count` jobs with these arguments and returns the jids the strategy let through
    # and the ones it refused.
    def fetch(count, args)
      jids = Array.new(count) { SecureRandom.hex(12) }
      refused, admitted = jids.partition { |jid| strategy.throttled?(jid, *args) }
      [admitted, refused]
    end

    before do
      clear_throttle_keys
      # The resolution of the last limit stays on the thread: each example starts without one.
      Thread.current[IntegrationThrottleKey::THREAD_KEY] = nil

      {integration_a => customer_a, integration_b => customer_b}.each do |integration, customer|
        create(:netsuite_customer, integration:, customer:)
          .update_column(:type, quickbooks_customer_type) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    after { clear_throttle_keys }

    describe "QuickBooks jobs" do
      it "runs at most 3 jobs of one company and still admits another company" do
        admitted_a, refused_a = fetch(4, args_a)
        admitted_b, refused_b = fetch(2, args_b)

        expect(admitted_a.size).to eq(3)
        expect(refused_a.size).to eq(1)
        expect(admitted_b.size).to eq(2)
        expect(refused_b).to be_empty

        expect(jids_in(key_a)).to match_array(admitted_a)
        expect(jids_in(key_b)).to match_array(admitted_b)
        expect(key_a).not_to eq(key_b)
        expect(jids_in(shared_key)).to match_array(admitted_a + admitted_b)
      end

      it "caps each company on its own count" do
        admitted_a, = fetch(1, args_a)
        admitted_b, refused_b = fetch(4, args_b)
        more_a, refused_a = fetch(1, args_a)

        expect(admitted_b.size).to eq(3)
        expect(refused_b.size).to eq(1)
        expect(more_a.size).to eq(1)
        expect(refused_a).to be_empty

        expect(jids_in(key_b)).to match_array(admitted_b)
        expect(jids_in(shared_key)).to match_array(admitted_a + admitted_b + more_a)
      end

      it "keeps a refused job out of the shared slots" do
        admitted, refused = fetch(6, args_a)

        expect(admitted.size).to eq(3)
        expect(refused.size).to eq(3)
        expect(jids_in(shared_key)).to match_array(admitted)
        expect(jids_in(shared_key) & refused).to be_empty
        expect(jids_in(key_a)).to match_array(admitted)
      end

      it "frees the slot of the company when a job finishes", cache: :memory do
        admitted, refused = fetch(4, args_a)
        expect(refused.size).to eq(1)

        strategy.finalize!(admitted.first, *args_a)

        expect(jids_in(key_a)).to match_array(admitted.drop(1))
        expect(jids_in(shared_key)).to match_array(admitted.drop(1))

        readmitted, refused_again = fetch(2, args_a)
        expect(readmitted.size).to eq(1)
        expect(refused_again.size).to eq(1)
      end

      it "frees the same slot when the cache is empty at the end of the job", cache: :memory do
        admitted, refused = fetch(4, args_a)
        expect(refused.size).to eq(1)

        Rails.cache.clear
        Thread.current[IntegrationThrottleKey::THREAD_KEY] = nil
        strategy.finalize!(admitted.first, *args_a)

        expect(jids_in(key_a)).to match_array(admitted.drop(1))
        expect(jids_in(shared_key)).to match_array(admitted.drop(1))

        readmitted, refused_again = fetch(2, args_a)
        expect(readmitted.size).to eq(1)
        expect(refused_again.size).to eq(1)
      end
    end

    describe "a resolution that fails after the limit was returned" do
      before do
        args_a
        calls = 0
        allow(Rails.cache).to receive(:fetch).and_wrap_original do |original, *fetch_args, **options, &block|
          calls += 1
          raise StandardError if calls > 1

          original.call(*fetch_args, **options, &block)
        end
      end

      it "counts the job under its company and writes no key ending in :none" do
        admitted, refused = fetch(1, args_a)

        expect(admitted.size).to eq(1)
        expect(refused).to be_empty
        expect(throttle_keys).to contain_exactly(shared_key, key_a)
        expect(throttle_keys.grep(/:none\z/)).to be_empty

        strategy.finalize!(admitted.first, *args_a)

        expect(jids_in(key_a)).to be_empty
        expect(jids_in(shared_key)).to be_empty
      end
    end

    describe "jobs of the other providers" do
      %i[netsuite xero hubspot anrok avalara].each do |provider|
        it "admits 5 #{provider} jobs and throttles the 6th under the shared key only" do
          customer = create(:customer, organization:)
          create(:"#{provider}_customer", customer:, integration: create(:"#{provider}_integration", organization:))

          admitted, refused = fetch(6, invoice_job_args(customer))

          expect(admitted.size).to eq(5)
          expect(refused.size).to eq(1)
          expect(jids_in(shared_key)).to match_array(admitted)
          expect(throttle_keys).to eq([shared_key])
        end
      end

      it "shares the 5 slots with QuickBooks jobs" do
        admitted_a, = fetch(3, args_a)
        admitted, refused = fetch(3, invoice_job_args(create(:customer, organization:)))

        expect(admitted.size).to eq(2)
        expect(refused.size).to eq(1)
        expect(jids_in(shared_key)).to match_array(admitted_a + admitted)
      end
    end

    describe "arguments that resolve to no company" do
      let(:unresolved) do
        {
          "nil" => [nil],
          "a string" => ["invoice"],
          "an empty hash" => [{}],
          "a malformed global id" => [{"invoice" => {"_aj_globalid" => "not a gid"}}],
          "an unknown record" => [{"invoice" => {"_aj_globalid" => "gid://#{GlobalID.app}/Invoice/#{SecureRandom.uuid}"}}],
          "no argument" => []
        }
      end

      it "falls back to the shared limit and never raises" do
        unresolved.each do |label, args|
          clear_throttle_keys
          admitted, refused = fetch(6, args)

          expect(admitted.size).to eq(5), label
          expect(refused.size).to eq(1), label
          expect(throttle_keys).to eq([shared_key]), label

          expect { strategy.finalize!(admitted.first, *args) }.not_to raise_error, label
          expect(jids_in(shared_key)).to match_array(admitted.drop(1)), label
        end
      end

      it "resets without arguments" do
        fetch(1, [])

        expect { strategy.reset! }.not_to raise_error
        expect(jids_in(shared_key)).to be_empty
      end
    end
  end
end

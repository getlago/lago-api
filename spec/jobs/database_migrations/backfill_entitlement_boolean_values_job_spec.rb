# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::BackfillEntitlementBooleanValuesJob do
  subject(:perform_job) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:entitlement) { create(:entitlement, organization:, feature:) }
  let(:enabled) { create(:privilege, organization:, feature:, code: "enabled", value_type: "boolean") }
  let(:beta) { create(:privilege, organization:, feature:, code: "beta", value_type: "boolean") }
  let(:label) { create(:privilege, organization:, feature:, code: "label", value_type: "string") }
  let(:enabled_value) { create(:entitlement_value, organization:, entitlement:, privilege: enabled, value: "t") }
  let(:beta_value) { create(:entitlement_value, organization:, entitlement:, privilege: beta, value: "f") }
  let(:label_value) { create(:entitlement_value, organization:, entitlement:, privilege: label, value: "t") }

  def stored_value(entitlement_value)
    Entitlement::EntitlementValue.unscoped.find(entitlement_value.id).read_attribute(:value)
  end

  before do
    enabled_value
    beta_value
    label_value
  end

  it "rewrites the boolean values stored as t and f" do
    perform_job

    expect(stored_value(enabled_value)).to eq("true")
    expect(stored_value(beta_value)).to eq("false")
  end

  it "leaves the values of other privileges" do
    perform_job

    expect(stored_value(label_value)).to eq("t")
  end

  it "does not enqueue another batch when the walk is over" do
    expect { perform_job }.not_to have_enqueued_job(described_class)
  end

  context "when the value is discarded" do
    before { beta_value.discard! }

    it "backfills it too" do
      perform_job

      expect(stored_value(beta_value)).to eq("false")
    end
  end

  context "when the batch is full" do
    before { stub_const("#{described_class}::BATCH_SIZE", 1) }

    it "chains to the next batch from the last id" do
      first_id = [enabled_value.id, beta_value.id].min

      expect { perform_job }.to have_enqueued_job(described_class).with(first_id, 1)
    end
  end

  context "when values are still stored as t or f after the first walk" do
    it "walks again from the beginning" do
      expect { described_class.perform_now([enabled_value.id, beta_value.id].max) }
        .to have_enqueued_job(described_class).with(nil, 2)
    end
  end

  context "when values are still stored as t or f after the second walk" do
    before { allow(Rails.logger).to receive(:error) }

    it "reports instead of finishing silently" do
      described_class.perform_now([enabled_value.id, beta_value.id].max, 2)

      expect(Rails.logger).to have_received(:error).with(/still stored as t or f/)
    end
  end

  context "when a request holds a value", transaction: false do
    it "skips it without waiting and leaves it to the second walk" do
      locked = Queue.new
      release = Queue.new
      holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActiveRecord::Base.transaction do
            Entitlement::EntitlementValue.lock.find(enabled_value.id)
            locked << true
            release.pop
          end
        end
      end
      locked.pop

      expect { perform_job }.to have_enqueued_job(described_class).with(nil, 2)

      release << true
      holder.join
      expect(stored_value(enabled_value)).to eq("t")
      expect(stored_value(beta_value)).to eq("false")
    end
  end

  context "when a batch dies" do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
    ensure
      ActiveJob::Uniqueness.unlock!(job_class_name: described_class.name)
      ActiveJob::Uniqueness.test_mode!
    end

    it "is unlocked by the death handler, so that it can be enqueued again" do
      job = described_class.perform_later(enabled_value.id)
      expect(described_class.perform_later(enabled_value.id)).to be(false)

      ActiveJob::Uniqueness.unlock_sidekiq_job!(
        "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "args" => [job.serialize]
      )

      expect(described_class.perform_later(enabled_value.id)).to be_a(described_class)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::SandboxLockService do
  subject(:result) do
    ApplicationRecord.transaction { described_class.call(organization:, **options) }
  end

  let(:options) { {} }
  let(:organization) { create(:organization) }

  it "returns the organization" do
    expect(result.organization).to eq(organization)
    expect(result.sandbox_organization).to be_nil
  end

  context "with lock_sandbox" do
    let(:options) { {lock_sandbox: true} }

    it "returns no sandbox when it has none" do
      expect(result.sandbox_organization).to be_nil
    end

    context "when it has a sandbox" do
      let(:organization) { create(:organization, :with_sandbox) }

      it "returns its sandbox" do
        expect(result.sandbox_organization).to eq(organization.sandbox_organization)
      end
    end
  end

  it "reads the row again, so it sees a change made since it was loaded" do
    Organization.find(organization.id).update!(name: "Renamed")

    expect(result.organization.name).to eq("Renamed")
  end

  context "with a sandbox" do
    let(:organization) { create(:organization, :sandbox) }

    it "refuses it" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("sandbox_managed_by_production")
    end

    context "when sandboxes are allowed" do
      let(:options) { {allow_sandbox: true} }

      it "returns it with its production" do
        expect(result.organization).to eq(organization)
        expect(result.production_organization).to eq(organization.production_organization)
      end
    end
  end

  context "with unsaved changes" do
    before { organization.name = "Unsaved" }

    it "raises" do
      expect { result }.to raise_error(RuntimeError, /unpersisted changes/)
    end
  end

  context "without a transaction", transaction: false do
    it "raises" do
      expect { described_class.call(organization:) }.to raise_error(ArgumentError, /inside a transaction/)
    end
  end

  context "with an allowed sandbox whose production another transaction holds", transaction: false do
    let(:organization) { create(:organization, :sandbox) }

    it "waits for the production before it locks the sandbox" do
      production_id = organization.production_organization_id
      locked = Queue.new
      release = Queue.new

      holder = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ApplicationRecord.transaction do
            Organization.lock.find(production_id)
            locked << true
            release.pop
          end
        end
      end
      Timeout.timeout(10) { locked.pop }

      waiter = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ApplicationRecord.transaction do
            described_class.call(organization: Organization.find(organization.id), allow_sandbox: true)
          end
        end
      end
      begin
        Timeout.timeout(10) do
          sleep(0.01) until ApplicationRecord.connection.select_value(
            "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
          ).positive?
        end

        sandbox_free = ApplicationRecord.transaction { Organization.lock("FOR UPDATE NOWAIT").find(organization.id) }
      ensure
        release << true
      end
      Timeout.timeout(10) { holder.join }
      waiter_result = Timeout.timeout(10) { waiter.value }

      expect(sandbox_free).to eq(organization)
      expect(waiter_result.production_organization.id).to eq(production_id)
    end
  end

  context "when another transaction turns the organization into a sandbox while it waits", transaction: false do
    let(:production) { create(:organization) }

    it "refuses it once the other transaction commits" do
      stale = Organization.find(organization.id)
      locked = Queue.new
      release = Queue.new

      writer = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ApplicationRecord.transaction do
            target = Organization.lock.find(organization.id)
            target.update!(environment: "sandbox", production_organization: production)
            locked << true
            release.pop
          end
        end
      end
      Timeout.timeout(10) { locked.pop }

      reader = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ApplicationRecord.transaction { described_class.call(organization: stale) }
        end
      end
      release << true

      Timeout.timeout(10) { writer.join }
      reader_result = Timeout.timeout(10) { reader.value }

      expect(reader_result.error.code).to eq("sandbox_managed_by_production")
    end
  end
end

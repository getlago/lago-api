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

      it "returns it" do
        expect(result.organization).to eq(organization)
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

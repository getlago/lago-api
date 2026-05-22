# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "recipes:api_keys:expire_all" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["recipes:api_keys:expire_all"] }
  let(:organization) { create(:organization, api_keys: []) }

  before do
    Rake.application.rake_require("tasks/recipes/api_keys")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { |r| "#{r}\n" })
  end

  context "when organization is not found" do
    before { stub_stdin("00000000") }

    it "aborts" do
      expect { task.invoke }.to raise_error(SystemExit)
    end
  end

  context "when user does not confirm the organization" do
    before { stub_stdin(organization.id, "n") }

    it "aborts" do
      expect { task.invoke }.to raise_error(SystemExit)
    end
  end

  context "when organization has no active api keys" do
    before { stub_stdin(organization.id, "y") }

    it "finishes without expiring anything" do
      expect { task.invoke }.not_to raise_error
    end
  end

  context "when organization has active api keys" do
    let!(:key_one) { create(:api_key, organization:) }
    let!(:key_two) { create(:api_key, organization:) }
    let!(:already_expired_key) { create(:api_key, :expired, organization:) }

    before do
      allow(ApiKeys::CacheService).to receive(:expire_cache)
      allow(Utils::SecurityLog).to receive(:produce)
    end

    context "when user confirms" do
      before { stub_stdin(organization.id, "y", "y") }

      it "expires all active keys" do
        task.invoke

        expect(key_one.reload).to be_expired
        expect(key_two.reload).to be_expired
      end

      it "does not touch already-expired keys" do
        original_updated_at = already_expired_key.updated_at
        task.invoke
        expect(ApiKey.unscoped.find(already_expired_key.id).updated_at)
          .to eq(original_updated_at)
      end

      it "invalidates the cache for each expired key" do
        task.invoke
        expect(ApiKeys::CacheService).to have_received(:expire_cache).with(key_one.value)
        expect(ApiKeys::CacheService).to have_received(:expire_cache).with(key_two.value)
      end

      it "emits a security log per expired key" do
        task.invoke
        expect(Utils::SecurityLog).to have_received(:produce).with(
          organization:,
          log_type: "api_key",
          log_event: "api_key.deleted",
          resources: {name: key_one.name, value_ending: key_one.value.last(4)}
        )
        expect(Utils::SecurityLog).to have_received(:produce).with(
          organization:,
          log_type: "api_key",
          log_event: "api_key.deleted",
          resources: {name: key_two.name, value_ending: key_two.value.last(4)}
        )
      end
    end

    context "when user declines confirmation" do
      before { stub_stdin(organization.id, "y", "n") }

      it "aborts without expiring keys" do
        expect { task.invoke }.to raise_error(SystemExit)
        expect(key_one.reload.expires_at).to be_nil
        expect(key_two.reload.expires_at).to be_nil
      end
    end
  end
end

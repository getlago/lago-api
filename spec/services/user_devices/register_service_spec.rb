# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserDevices::RegisterService do
  subject(:result) { described_class.call(user:, skip_log:) }

  include_context "with mocked security logger"

  let(:user) { membership.user }
  let(:skip_log) { false }
  let(:device_info) do
    {
      user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
      ip_address: "192.168.1.1",
      browser: "Chrome 120",
      os: "macOS",
      device_type: "desktop"
    }
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create(:membership) }

  before do
    membership
    CurrentContext.device_info = device_info
    allow(organization).to receive(:security_logs_enabled?).and_return(true)
    allow(user).to receive(:active_organizations).and_return([organization])
  end

  context "when device_info is nil" do
    let(:device_info) { nil }

    it "returns result without creating a device" do
      expect { result }.not_to change(UserDevice, :count)
    end
  end

  context "when device is new" do
    it "creates a user device" do
      expect { result }.to change(UserDevice, :count).by(1)

      device = user.user_devices.sole
      expect(device.fingerprint).to eq(Digest::SHA256.hexdigest(device_info[:user_agent]))
      expect(device.browser).to eq("Chrome 120")
      expect(device.os).to eq("macOS")
      expect(device.device_type).to eq("desktop")
      expect(device.last_ip_address).to eq("192.168.1.1")
    end

    it "produces security logs" do
      result

      expect(security_logger).to have_received(:produce).with(
        organization:,
        log_type: "user",
        log_event: "user.new_device_logged_in",
        user:
      )
    end

    context "with skip_log: true" do
      let(:skip_log) { true }

      it "creates a user device" do
        expect { result }.to change(UserDevice, :count).by(1)
      end

      it "does not produce security logs" do
        result

        expect(security_logger).not_to have_received(:produce)
      end
    end
  end

  context "when device is known" do
    let!(:existing_device) do
      create(:user_device,
        user:,
        fingerprint: Digest::SHA256.hexdigest(device_info[:user_agent]),
        last_logged_at: 1.day.ago)
    end

    it "does not create a new device" do
      expect { result }.not_to change(UserDevice, :count)
    end

    it "updates last_logged_at" do
      result

      expect(existing_device.reload.last_logged_at).to be_within(1.second).of(Time.current)
    end

    it "does not produce security logs" do
      result

      expect(security_logger).not_to have_received(:produce)
    end
  end

  context "when another sign-in from the same browser inserts the device first" do
    # Run as in a request, whose executor caches reads until a write through Active Record.
    subject(:result) { ActiveRecord::Base.cache { described_class.call(user:, skip_log:) } }

    let(:fingerprint) { Digest::SHA256.hexdigest(device_info[:user_agent]) }
    let(:passes_validation) { false }
    let(:concurrent_device) { UserDevice.uncached { UserDevice.find_by!(user:, fingerprint:) } }

    before do
      freeze_time
      # The other request commits right after this one's lookup: inserted over the raw connection, as another
      # connection would, so the cached lookup still answers that there is no device.
      allow(user.user_devices).to receive(:find_or_initialize_by).and_wrap_original do |original, *args|
        original.call(*args).tap do |device|
          ApplicationRecord.connection.raw_connection.exec_params(
            "INSERT INTO user_devices (id, user_id, fingerprint, last_logged_at, created_at, updated_at) " \
            "VALUES (gen_random_uuid(), $1, $2, $3, $3, $3)",
            [user.id, fingerprint, 1.day.ago.iso8601(6)]
          )
          allow(device).to receive(:valid?).and_return(true) if passes_validation
        end
      end
    end

    shared_examples "a device registered by the other sign-in" do
      it "updates the device the other sign-in created" do
        expect(result).to be_success
        expect(UserDevice.where(user:).count).to eq(1)
        expect(concurrent_device).to have_attributes(last_logged_at: Time.current, browser: "Chrome 120", last_ip_address: "192.168.1.1")
      end

      it "does not log a new device" do
        result

        expect(security_logger).not_to have_received(:produce)
      end

      it "leaves the caller's transaction usable" do
        ActiveRecord::Base.transaction do
          expect(result).to be_success
          expect(UserDevice.where(user:).count).to eq(1)
        end
      end
    end

    context "when the other device is committed before the uniqueness validation" do
      it_behaves_like "a device registered by the other sign-in"
    end

    context "when both requests pass the uniqueness validation" do
      let(:passes_validation) { true }

      it_behaves_like "a device registered by the other sign-in"
    end
  end

  context "when the write hits another unique index" do
    let(:devices) { user.user_devices }
    let(:device) { UserDevice.new(user:) }

    before do
      allow(user).to receive(:user_devices).and_return(devices)
      allow(devices).to receive(:find_or_initialize_by).and_return(device)
      allow(device).to receive(:update!).and_raise(ActiveRecord::RecordNotUnique)
    end

    it "raises" do
      expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end

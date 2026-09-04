# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::EmailNotificationJob do
  let(:audit_log) { create(:cs_admin_audit_log) }
  let(:delivery) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

  before do
    allow(AdminMailer)
      .to receive(:feature_toggled)
      .with(audit_log:, actor_email: "cs@getlago.com")
      .and_return(delivery)
  end

  it "delivers the feature toggled email for the audit log" do
    described_class.perform_now(audit_log.id, "cs@getlago.com")

    expect(AdminMailer).to have_received(:feature_toggled).with(audit_log:, actor_email: "cs@getlago.com")
    expect(delivery).to have_received(:deliver_now)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SlackNotificationJob do
  let(:audit_log) { create(:cs_admin_audit_log) }
  let(:result) { Admin::SlackNotificationService::Result.new }

  before do
    allow(Admin::SlackNotificationService).to receive(:call!).with(audit_log:).and_return(result)
  end

  it "calls the Slack notification service with the audit log" do
    described_class.perform_now(audit_log.id)

    expect(Admin::SlackNotificationService).to have_received(:call!).with(audit_log:)
  end
end

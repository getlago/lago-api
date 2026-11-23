# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::CreateOrganizationService do
  subject(:result) { described_class.call(user:, name:, role:, referral_source: source) }

  include_context "with self-serve enabled"
  include_context "with mocked security logger"

  let(:user) { create(:user, :self_serve, email: "jane@getlago.com") }
  let(:name) { "Acme" }
  let(:role) { "engineering" }
  let(:source) { "github" }
  let(:admin_role) { create(:role, :admin) }

  before do
    admin_role
    allow(Rails.application.config).to receive(:lago_front_url).and_return("https://app.eu.getlago.com")
    stub_const("ENV", ENV.to_h.merge("LAGO_CLOUD" => "true"))
  end

  it "creates the production organization and its sandbox, with the user admin of both" do
    expect { result }.to change(Organization, :count).by(2)

    expect(result).to be_success
    expect(result.organization).to have_attributes(name: "Acme", environment: "production", self_serve: true)
    expect(result.sandbox_organization).to have_attributes(name: "Acme Sandbox", environment: "sandbox",
      production_organization_id: result.organization.id)
    expect(user.memberships.active.map { [it.organization_id, it.roles.map(&:code)] })
      .to match_array([[result.organization.id, ["admin"]], [result.sandbox_organization.id, ["admin"]]])
  end

  it "opens the production organization while the payment method switch is off" do
    expect(result.organization.reload.activation_status).to eq("active")
    expect(result.sandbox_organization.reload.activation_status).to eq("active")
  end

  context "with the payment method switch on" do
    let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_REQUIRE_PAYMENT_METHOD" => "true") }

    it "creates the production waiting for a payment method and the sandbox open" do
      expect(result).to be_success
      expect(result.organization.reload.activation_status).to eq("pending_payment_method")
      expect(result.sandbox_organization.reload.activation_status).to eq("active")
    end

    it "tells analytics the production waits for a payment method" do
      result

      expect(SegmentTrackJob).to have_been_enqueued
        .with(hash_including(event: "organization_registered",
          properties: hash_including(activation_status: "pending_payment_method")))
    end
  end

  it "answers with a user who no longer needs an organization" do
    expect(result.user).to eq(user)
    expect(result.user.needs_organization?).to be(false)
  end

  it "logs the signup and tells analytics, only after commit" do
    expect { result }.to have_enqueued_job_after_commit(SegmentIdentifyJob)

    membership = user.memberships.find_by!(organization: result.organization)
    expect(SegmentIdentifyJob).to have_been_enqueued.with(membership_id: "membership/#{membership.id}")
    expect(security_logger).to have_received(:produce).with(
      organization: result.organization,
      log_type: "user",
      log_event: "user.signed_up",
      user:,
      resources: {email: "jane@getlago.com", roles: ["admin"]},
      skip_organization_check: true
    )
    expect(SegmentTrackJob).to have_been_enqueued.with(
      membership_id: "membership/#{membership.id}",
      event: "organization_registered",
      properties: {
        organization_name: "Acme",
        organization_id: result.organization.id,
        email: "jane@getlago.com",
        self_serve: true,
        sandbox_organization_id: result.sandbox_organization.id,
        activation_status: "active",
        role: "engineering",
        source: "github",
        region: "app.eu.getlago.com"
      }
    )
  end

  context "when LAGO_FRONT_URL cannot be parsed" do
    before { allow(Rails.application.config).to receive(:lago_front_url).and_return("https://exa mple.com") }

    it "creates the pair and sends no region" do
      expect(result).to be_success
      expect(SegmentTrackJob).to have_been_enqueued
        .with(hash_including(event: "organization_registered", properties: hash_including(region: nil)))
    end
  end

  context "without a source" do
    let(:source) { nil }

    it "sends a nil source to analytics" do
      expect(result).to be_success
      expect(SegmentTrackJob).to have_been_enqueued
        .with(hash_including(event: "organization_registered", properties: hash_including(source: nil)))
    end
  end

  context "with an invalid name" do
    let(:name) { "  " }

    it "refuses it and creates nothing" do
      expect { result }.not_to change(Organization, :count)

      expect(result.error.messages).to eq(name: ["value_is_mandatory"])
      expect(user.memberships).to be_empty
    end
  end

  context "with an unknown role" do
    let(:role) { "astronaut" }

    it "refuses it" do
      expect(result.error.messages).to eq(role: ["value_is_invalid"])
    end
  end

  context "with an unknown source" do
    let(:source) { "carrier_pigeon" }

    it "refuses it" do
      expect(result.error.messages).to eq(source: ["value_is_invalid"])
    end
  end

  context "with a user who already has an organization" do
    before { create(:membership, user:) }

    it "refuses with user_not_eligible and creates nothing" do
      expect { result }.not_to change(Organization, :count)

      expect(result.error.code).to eq("user_not_eligible")
    end
  end

  context "with a user whose membership was revoked" do
    before { create(:membership, :revoked, user:) }

    it "refuses with user_not_eligible" do
      expect(result.error.code).to eq("user_not_eligible")
    end
  end

  context "with a user who did not sign up through self-serve" do
    let(:user) { create(:user, email: "jane@getlago.com") }

    it "refuses with user_not_eligible" do
      expect(result.error.code).to eq("user_not_eligible")
    end
  end

  context "when the membership cannot be saved" do
    before do
      invalid = Membership.new.tap { it.errors.add(:user_id, :taken) }
      allow(Membership).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid))
    end

    it "answers a validation failure and creates nothing" do
      expect { result }.not_to change(Organization, :count)
      expect(result.error.messages).to eq(user_id: ["value_already_exist"])
    end
  end

  context "when self-serve is off" do
    let(:self_serve_env) { {"LAGO_SELF_SERVE_ENABLED" => "false"} }

    it "refuses with self_serve_disabled" do
      expect(result.error.code).to eq("self_serve_disabled")
    end
  end

  context "when an invite is accepted while Step 3 waits", transaction: false do
    let(:invite) { create(:invite, email: user.email, roles: %w[admin]) }
    let(:accepted) { Concurrent::CountDownLatch.new }
    let(:acceptance) do
      latch = accepted
      invite_id = invite.id
      user_id = user.id
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ApplicationRecord.transaction do
            Memberships::CreateFromInviteService.call!(invite: Invite.find(invite_id), user: User.find(user_id))
            latch.count_down
            await_a_blocked_session
          end
        end
      end
    end

    before do
      acceptance
      raise "the invite was never accepted" unless accepted.wait(5)
    end

    after { acceptance.join }

    def await_a_blocked_session
      50.times do
        break if ApplicationRecord.with_connection { |connection| connection.select_value(<<~SQL) }
          SELECT EXISTS (SELECT 1 FROM pg_locks WHERE NOT granted AND pg_backend_pid() = ANY(pg_blocking_pids(pid)))
        SQL

        sleep(0.1)
      end
    end

    it "waits for the acceptance, then refuses with user_not_eligible and creates no pair" do
      expect(result.error.code).to eq("user_not_eligible")
      expect(Organization.where.not(id: invite.organization_id)).to be_empty
    end
  end

  context "when Step 3 is submitted twice at the same time", transaction: false do
    it "creates a single pair and refuses the other submission" do
      results = Array.new(2) do
        Thread.new do
          ApplicationRecord.connection_pool.with_connection do
            described_class.call(user: User.find(user.id), name:, role:, referral_source: source)
          end
        end
      end.map(&:value)

      expect(results.map(&:success?)).to contain_exactly(true, false)
      expect(results.reject(&:success?).sole.error.code).to eq("user_not_eligible")
      expect(Organization.count).to eq(2)
    end
  end
end

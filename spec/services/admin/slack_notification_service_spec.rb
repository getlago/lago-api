# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SlackNotificationService do
  subject(:service) { described_class.new(audit_log:) }

  let(:organization) { create(:organization, name: "ACME Corp") }
  let(:audit_log) do
    create(:cs_admin_audit_log,
      organization:,
      action: :toggle_on,
      feature_key: "netsuite",
      actor_email: "admin@lago.com",
      reason: "Enabling for customer onboarding POC")
  end

  let(:webhook_url) { "https://hooks.slack.com/services/test/webhook" }

  describe "#call" do
    context "when webhook URL is configured" do
      before do
        stub_const("ENV", ENV.to_h.merge("CS_ADMIN_SLACK_WEBHOOK_URL" => webhook_url))
        stub_request(:post, webhook_url).to_return(status: 200, body: "ok")
      end

      it "sends a POST request to the Slack webhook with a Block Kit payload" do
        result = service.call

        expect(result).to be_success
        expect(a_request(:post, webhook_url).with { |req|
          body = JSON.parse(req.body)
          body["blocks"].is_a?(Array) &&
            body["blocks"].first["type"] == "section" &&
            body["blocks"].first["text"]["type"] == "mrkdwn"
        }).to have_been_made.once
      end

      it "includes the feature key, organization name, actor email and reason in the message" do
        service.call

        expect(a_request(:post, webhook_url).with { |req|
          text = JSON.parse(req.body)["blocks"].first["text"]["text"]
          text.include?("netsuite") &&
            text.include?("ACME Corp") &&
            text.include?("admin@lago.com") &&
            text.include?("Enabling for customer onboarding POC")
        }).to have_been_made.once
      end

      context "when a sandbox was created" do
        let(:audit_log) do
          sandbox = create(:organization, :sandbox, production_organization: organization, name: "ACME Corp Sandbox")
          create(:cs_admin_audit_log, organization: sandbox, action: :org_created, feature_type: "organization",
            feature_key: "organization", before_value: nil, actor_email: "admin@lago.com",
            reason: "Enabling for customer onboarding POC")
        end

        it "names the sandbox and its production organization" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            JSON.parse(req.body)["blocks"].first["text"]["text"].include?("Sandbox created] *ACME Corp Sandbox* for *ACME Corp*")
          }).to have_been_made.once
        end
      end

      context "when the change was mirrored to a sandbox" do
        let(:batch_id) { SecureRandom.uuid }
        let(:audit_log) do
          create(:cs_admin_audit_log, organization:, action: :toggle_on, feature_key: "netsuite",
            actor_email: "admin@lago.com", reason: "Enabling for customer onboarding POC", batch_id:)
        end

        before do
          audit_log
          sandbox = create(:organization, :sandbox, production_organization: organization, name: "ACME <Sandbox>")
          create(:cs_admin_audit_log, organization: sandbox, action: :toggle_on, feature_key: "netsuite",
            actor_email: "admin@lago.com", reason: "Enabling for customer onboarding POC", batch_id:)
        end

        it "names the sandbox, escaped" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            JSON.parse(req.body)["blocks"].first["text"]["text"].include?("(mirrored to *ACME &lt;Sandbox&gt;*)")
          }).to have_been_made.once
        end
      end

      context "when a rollback shares the batch of an entry mirrored before it" do
        let(:batch_id) { SecureRandom.uuid }
        let(:audit_log) do
          create(:cs_admin_audit_log, organization:, action: :rollback, feature_key: "netsuite",
            actor_email: "admin@lago.com", reason: "Rolling back the onboarding POC", batch_id:)
        end

        before do
          sandbox = create(:organization, :sandbox, production_organization: organization)
          create(:cs_admin_audit_log, organization: sandbox, action: :toggle_on, feature_key: "netsuite",
            actor_email: "admin@lago.com", reason: "Enabling for customer onboarding POC", batch_id:,
            created_at: 1.day.ago)
        end

        it "does not say it was mirrored" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            JSON.parse(req.body)["blocks"].first["text"]["text"].include?("mirrored")
          }).not_to have_been_made
        end
      end

      context "when action is toggle_off" do
        let(:audit_log) do
          create(:cs_admin_audit_log,
            organization:,
            action: :toggle_off,
            feature_key: "netsuite",
            actor_email: "admin@lago.com",
            after_value: false,
            reason: "Disabling for customer offboarding test")
        end

        it "uses the disabled action text with ❌ emoji" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            text = JSON.parse(req.body)["blocks"].first["text"]["text"]
            text.include?("disabled") && text.include?("\u274c")
          }).to have_been_made.once
        end
      end

      context "when action is org_created" do
        let(:audit_log) do
          create(:cs_admin_audit_log,
            organization:,
            action: :org_created,
            feature_key: "netsuite",
            actor_email: "admin@lago.com",
            reason: "New org onboarded with premium access")
        end

        it "uses the set on new org action text with ✅ emoji" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            text = JSON.parse(req.body)["blocks"].first["text"]["text"]
            text.include?("set on new org") && text.include?("\u2705")
          }).to have_been_made.once
        end
      end

      context "when the organization name contains Slack markup" do
        let(:organization) { create(:organization, name: "Acme <https://evil.test|Grant access>") }

        it "escapes the markup so it cannot render as a link" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            text = JSON.parse(req.body)["blocks"].first["text"]["text"]
            text.include?("Acme &lt;https://evil.test|Grant access&gt;") &&
              !text.include?("<https://evil.test|Grant access>")
          }).to have_been_made.once
        end
      end

      context "when the reason spans several lines" do
        let(:audit_log) do
          create(:cs_admin_audit_log,
            organization:,
            action: :toggle_on,
            feature_key: "netsuite",
            actor_email: "admin@lago.com",
            reason: "Approved\nby\nsomeone else")
        end

        it "collapses the newlines into a single line" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            text = JSON.parse(req.body)["blocks"].first["text"]["text"]
            text.include?("Approved by someone else") && !text.include?("\n")
          }).to have_been_made.once
        end
      end

      context "when the log is the organization creation itself" do
        let(:audit_log) do
          create(:cs_admin_audit_log,
            organization:,
            action: :org_created,
            feature_type: :organization,
            feature_key: "organization",
            actor_email: "admin@lago.com",
            reason: "New enterprise customer onboarding")
        end

        it "uses a dedicated organization created message" do
          service.call

          expect(a_request(:post, webhook_url).with { |req|
            text = JSON.parse(req.body)["blocks"].first["text"]["text"]
            text == "[✅ Organization created] *ACME Corp* by admin@lago.com — reason: \"New enterprise customer onboarding\""
          }).to have_been_made.once
        end
      end
    end

    context "when webhook URL is NOT configured" do
      before do
        stub_const("ENV", ENV.to_h.except("CS_ADMIN_SLACK_WEBHOOK_URL"))
      end

      it "returns a success result without making any HTTP request" do
        result = service.call

        expect(result).to be_success
        expect(a_request(:post, /slack/)).not_to have_been_made
      end
    end

    [429, 500, 503].each do |status|
      context "when Slack returns HTTP #{status}" do
        before do
          stub_const("ENV", ENV.to_h.merge("CS_ADMIN_SLACK_WEBHOOK_URL" => webhook_url))
          stub_request(:post, webhook_url).to_return(status:, body: "temporarily unavailable")
        end

        it "raises a retryable error without disclosing the webhook" do
          expect { service.call }.to raise_error(described_class::DeliveryError) do |error|
            expect(error.message).to include(audit_log.id, status.to_s)
            expect(error.message).not_to include(webhook_url)
            expect(error.cause).to be_nil
          end
        end
      end
    end

    context "when Slack times out" do
      before do
        stub_const("ENV", ENV.to_h.merge("CS_ADMIN_SLACK_WEBHOOK_URL" => webhook_url))
        stub_request(:post, webhook_url).to_timeout
      end

      it "raises a retryable error without disclosing the webhook" do
        expect { service.call }.to raise_error(described_class::DeliveryError) do |error|
          expect(error.message).not_to include(webhook_url)
          expect(error.cause).to be_nil
        end
      end
    end

    context "when the Slack host does not resolve" do
      before do
        stub_const("ENV", ENV.to_h.merge("CS_ADMIN_SLACK_WEBHOOK_URL" => webhook_url))
        stub_request(:post, webhook_url).to_raise(Socket::ResolutionError.new("getaddrinfo: Temporary failure in name resolution"))
      end

      it "raises a retryable error" do
        expect { service.call }.to raise_error(described_class::DeliveryError)
      end
    end

    context "when Slack rejects the payload" do
      before do
        stub_const("ENV", ENV.to_h.merge("CS_ADMIN_SLACK_WEBHOOK_URL" => webhook_url))
        stub_request(:post, webhook_url).to_return(status: 400, body: "invalid_payload")
      end

      it "returns a failure without retrying or disclosing the webhook" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("slack_notification_failed")
        expect(result.error.message).not_to include(webhook_url)
        expect(a_request(:post, webhook_url)).to have_been_made.once
      end
    end
  end
end

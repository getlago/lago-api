# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignupMailer do
  let(:pending_signup) { create(:pending_signup, email: "Jane@GetLago.com") }
  let(:front_url) { Rails.application.config.lago_front_url }

  describe "#verification" do
    subject(:mail) { described_class.with(pending_signup:).verification }

    it "sends the link to the attempt's address" do
      body = CGI.unescapeHTML(mail.body.encoded)
      token = body[%r{#{Regexp.escape(front_url)}/verify-email\?token=([A-Za-z0-9_-]{43})}, 1]

      expect(mail.to).to eq(["Jane@GetLago.com"])
      expect(mail.from).to eq([ENV["LAGO_FROM_EMAIL"]])
      expect(mail.subject).to eq("Verify your email to finish creating your Lago account")
      expect(PendingSignupToken.for_token(token)).to eq(pending_signup.tokens.pending.sole)
      expect(body).to include("This link expires in 24 hours and can be used only once.")
      expect(body).to include("Didn't sign up for Lago? Ignore this email. Nothing is created until this link is clicked.")
    end

    it "takes only the pending signup as a param" do
      expect(mail.instance_variable_get(:@params)).to eq(pending_signup:)
    end

    context "when the email is blank" do
      before { pending_signup.email = "" }

      it "sends nothing and issues no link" do
        expect(mail.to).to be_nil
        expect(pending_signup.tokens).to be_empty
      end
    end
  end

  describe "#account_exists" do
    subject(:mail) { described_class.with(pending_signup:).account_exists }

    it "points to login and password reset, with no link token" do
      body = CGI.unescapeHTML(mail.body.encoded)

      expect(mail.subject).to eq("You already have a Lago account")
      expect(body).to include("You already have a Lago account, log in here:")
      expect(body).to include("#{front_url}/login", "#{front_url}/forgot-password")
      expect(body).not_to include("verify-email")
      expect(pending_signup.tokens).to be_empty
    end
  end
end

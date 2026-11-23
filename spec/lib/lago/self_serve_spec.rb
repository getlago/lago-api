# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lago::SelfServe do
  describe ".enabled?" do
    it "is off when the variable is unset, empty or false" do
      expect([nil, "", "false"].map { described_class.enabled?(value: it) }).to all(be(false))
    end

    it "is on for true, whatever its case and surrounding spaces" do
      expect(["true", " TRUE ", "True\n"].map { described_class.enabled?(value: it) }).to all(be(true))
    end

    it "is off for other truthy-looking values" do
      expect(%w[1 yes on no].map { described_class.enabled?(value: it) }).to all(be(false))
    end

    context "when reading the environment" do
      it "is on when LAGO_SELF_SERVE_ENABLED is true" do
        stub_const("ENV", ENV.to_h.merge("LAGO_SELF_SERVE_ENABLED" => "true"))

        expect(described_class.enabled?).to be(true)
      end

      it "is off when LAGO_SELF_SERVE_ENABLED is unset" do
        stub_const("ENV", ENV.to_h.except("LAGO_SELF_SERVE_ENABLED"))

        expect(described_class.enabled?).to be(false)
      end
    end
  end

  describe ".require_payment_method?" do
    it "is off when the variable is unset, empty or false" do
      expect([nil, "", "false"].map { described_class.require_payment_method?(value: it) }).to all(be(false))
    end

    it "is on for true, whatever its case and surrounding spaces" do
      expect(["true", " TRUE ", "True\n"].map { described_class.require_payment_method?(value: it) }).to all(be(true))
    end

    it "is off for other truthy-looking values" do
      expect(%w[1 yes on no].map { described_class.require_payment_method?(value: it) }).to all(be(false))
    end

    it "reads LAGO_SELF_SERVE_REQUIRE_PAYMENT_METHOD" do
      stub_const("ENV", ENV.to_h.merge("LAGO_SELF_SERVE_REQUIRE_PAYMENT_METHOD" => "true"))

      expect(described_class.require_payment_method?).to be(true)
    end
  end

  describe ".signup_disabled?" do
    it "is true for true only, with the exact comparison of the legacy check" do
      expect(described_class.signup_disabled?(value: "true")).to be(true)
      expect([nil, "false", "TRUE"].map { described_class.signup_disabled?(value: it) }).to all(be(false))
    end

    it "reads LAGO_DISABLE_SIGNUP" do
      stub_const("ENV", ENV.to_h.merge("LAGO_DISABLE_SIGNUP" => "true"))

      expect(described_class.signup_disabled?).to be(true)
    end
  end

  describe ".billing_accounts_key" do
    it "is the key, stripped, or nil when it is blank" do
      expect(described_class.billing_accounts_key(value: " key ")).to eq("key")
      expect([nil, "", "  "].map { described_class.billing_accounts_key(value: it) }).to all(be_nil)
    end

    it "reads LAGO_ADMIN_API_BILLING_ACCOUNTS_KEY" do
      stub_const("ENV", ENV.to_h.merge("LAGO_ADMIN_API_BILLING_ACCOUNTS_KEY" => "key"))

      expect(described_class.billing_accounts_key).to eq("key")
    end
  end

  describe ".front_host" do
    it "is the downcased host of the front URL" do
      expect(described_class.front_host(url: "https://App.EU.getlago.com")).to eq("app.eu.getlago.com")
    end

    it "is nil for a URL without a scheme or a malformed one" do
      expect(["app.eu.getlago.com", "https://exa mple.com", nil].map { described_class.front_host(url: it) })
        .to eq([nil, nil, nil])
    end
  end

  describe ".region" do
    before { allow(Rails.application.config).to receive(:lago_front_url).and_return("https://app.eu.getlago.com") }

    it "returns the front host on Lago Cloud only" do
      expect(described_class.region(cloud: true)).to eq("app.eu.getlago.com")
      expect(described_class.region(cloud: false)).to be_nil
    end

    it "reads LAGO_CLOUD" do
      stub_const("ENV", ENV.to_h.merge("LAGO_CLOUD" => "true"))

      expect(described_class.region).to eq("app.eu.getlago.com")
    end
  end

  describe ".validate!" do
    let(:front_url) { "https://app.getlago.com" }

    # Examples that leave a variable out read it, which the runner's environment (or its .env) must not decide.
    before do
      stub_const("ENV", ENV.to_h.except(
        "LAGO_DISABLE_SIGNUP", "LAGO_SELF_SERVE_REQUIRE_PAYMENT_METHOD", "LAGO_ADMIN_API_BILLING_ACCOUNTS_KEY"
      ))
    end

    it "accepts unset, empty, true and false" do
      [nil, "", "true", "false", " False "].each do |value|
        expect { described_class.validate!(value:, front_url:, local: false) }.not_to raise_error
      end
    end

    it "refuses any other value" do
      %w[1 yes enabled].each do |value|
        expect { described_class.validate!(value:, front_url:, local: false) }
          .to raise_error(ArgumentError, /LAGO_SELF_SERVE_ENABLED/)
      end
    end

    context "when the gate is off" do
      it "never checks the front URL" do
        [nil, "", "http://x/y"].each do |url|
          expect { described_class.validate!(value: nil, front_url: url, local: false) }.not_to raise_error
        end
      end

      it "leaves LAGO_DISABLE_SIGNUP as self-hosted reads it" do
        %w[TRUE 1 yes].each do |disable_signup|
          expect { described_class.validate!(value: nil, front_url: nil, disable_signup:, local: false) }
            .not_to raise_error
        end
      end
    end

    context "when the gate is on outside development and test" do
      it "accepts an https origin, with or without a port" do
        ["https://app.eu.getlago.com", "https://app.eu.getlago.com:8443"].each do |url|
          expect { described_class.validate!(value: "true", front_url: url, local: false) }.not_to raise_error
        end
      end

      it "refuses a missing, http or non-origin front URL" do
        [
          nil, "", "   ", "http://app.eu.getlago.com", "https://app.eu.getlago.com/", "https://app.eu.getlago.com/app",
          "https://app.eu.getlago.com?x=1", "https://app.eu.getlago.com#x", "https://user@app.eu.getlago.com",
          "app.eu.getlago.com", "https://", "https://exa mple.com"
        ].each do |url|
          expect { described_class.validate!(value: "true", front_url: url, local: false) }
            .to raise_error(ArgumentError, /LAGO_FRONT_URL/)
        end
      end

      it "refuses an origin not written as browsers send it" do
        ["https://app.eu.getlago.com:443", "HTTPS://app.eu.getlago.com", "https://App.eu.getlago.com"].each do |url|
          expect { described_class.validate!(value: "true", front_url: url, local: false) }
            .to raise_error(ArgumentError, /LAGO_FRONT_URL/)
        end
      end

      it "accepts LAGO_DISABLE_SIGNUP unset, empty, true or false" do
        [nil, "", "true", "false"].each do |disable_signup|
          expect { described_class.validate!(value: "true", front_url:, disable_signup:, local: false) }
            .not_to raise_error
        end
      end

      it "refuses any other spelling of LAGO_DISABLE_SIGNUP, which signup would read as off" do
        ["TRUE", " true", "1", "yes"].each do |disable_signup|
          expect { described_class.validate!(value: "true", front_url:, disable_signup:, local: false) }
            .to raise_error(ArgumentError, /LAGO_DISABLE_SIGNUP/)
        end
      end
    end

    context "when the gate is on in development or test" do
      it "accepts a missing or http front URL" do
        [nil, "http://localhost:3000"].each do |url|
          expect { described_class.validate!(value: "true", front_url: url, local: true) }.not_to raise_error
        end
      end

      it "still refuses a front URL with a path" do
        expect { described_class.validate!(value: "true", front_url: "http://localhost:3000/x", local: true) }
          .to raise_error(ArgumentError, /LAGO_FRONT_URL/)
      end
    end

    context "with the payment method switch" do
      def validate(value: "true", require_payment_method: "true", billing_accounts_key: "key")
        described_class.validate!(value:, front_url:, disable_signup: "false", require_payment_method:,
          billing_accounts_key:, local: false)
      end

      it "accepts it unset, empty or false whatever the rest" do
        [nil, "", "false", " False "].each do |require_payment_method|
          expect { validate(value: nil, require_payment_method:, billing_accounts_key: nil) }.not_to raise_error
          expect { validate(require_payment_method:, billing_accounts_key: nil) }.not_to raise_error
        end
      end

      it "refuses any other value while self-serve is on" do
        %w[1 yes].each do |require_payment_method|
          expect { validate(require_payment_method:) }
            .to raise_error(ArgumentError, /LAGO_SELF_SERVE_REQUIRE_PAYMENT_METHOD must be true or false/)
        end
      end

      it "ignores any other value while self-serve is off, as self-hosted does" do
        %w[1 yes].each do |require_payment_method|
          expect { validate(value: nil, require_payment_method:, billing_accounts_key: nil) }.not_to raise_error
        end
      end

      it "accepts it on with self-serve on and the activation key set" do
        expect { validate }.not_to raise_error
      end

      it "refuses it on while self-serve is off" do
        expect { validate(value: "false") }.to raise_error(ArgumentError, /needs LAGO_SELF_SERVE_ENABLED/)
      end

      it "refuses it on without the activation key" do
        [nil, "", "  "].each do |billing_accounts_key|
          expect { validate(billing_accounts_key:) }
            .to raise_error(ArgumentError, /needs LAGO_ADMIN_API_BILLING_ACCOUNTS_KEY/)
        end
      end
    end
  end

  describe "initializer" do
    it "stops the boot on a malformed value" do
      stub_const("ENV", ENV.to_h.merge("LAGO_SELF_SERVE_ENABLED" => "yes"))

      expect { load Rails.root.join("config/initializers/self_serve.rb") }
        .to raise_error(ArgumentError, /LAGO_SELF_SERVE_ENABLED/)
    end
  end
end

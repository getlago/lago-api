# frozen_string_literal: true

RSpec.shared_examples "organization premium feature" do |feature_name|
  subject { organization.public_send("#{feature_name}_enabled?") }

  it { is_expected.to eq(false) }

  context "when premium features are enabled", :lago_premium do

    it { is_expected.to eq(false) }

    context "with #{feature_name} integration enabled", :lago_premium do
      let(:organization) do
        described_class.new(premium_integrations: [feature_name])
      end

      it { is_expected.to eq(true) }
    end
  end
end

# frozen_string_literal: true

RSpec.shared_examples "requires current user" do
  it "requires a current user" do
    expect(described_class.ancestors).to include(AuthenticableApiUser)
  end
end

RSpec.shared_examples "requires current organization" do
  it "requires a current organization" do
    expect(described_class.ancestors).to include(RequiredOrganization)
  end

  context "with an organization waiting for a payment method" do
    include_context "with self-serve enabled"

    let(:waiting_organization) do
      # The class's own checks must pass first, so it gets the flag a catalog operation requires.
      feature_flags = described_class.ancestors.include?(RequiresProductCatalog) ? ["product_catalog"] : []
      create(:organization, :self_serve, activation_status: "pending_payment_method", feature_flags:)
    end
    let(:waiting_membership) { create(:membership, organization: waiting_organization) }
    let(:waiting_context) do
      values = {
        current_user: waiting_membership.user,
        current_organization: waiting_organization,
        current_membership: waiting_membership,
        permissions: Permission.permissions_hash(:admin)
      }
      GraphQL::Query.new(LagoApiSchema, "{ __typename }", context: values).context
    end

    it "refuses it with organization_inactive" do
      operation = described_class.new(object: nil, context: waiting_context, field: nil)

      expect { operation.send(:ready?) }.to raise_error(GraphQL::ExecutionError) { |error|
        expect(error.extensions).to include(status: 403, code: "organization_inactive")
      }
    end
  end
end

RSpec.shared_examples "requires permission" do |permission|
  it "requires #{permission} permission" do
    actual = Array.wrap(described_class::REQUIRED_PERMISSION).sort
    expected = Array.wrap(permission).sort
    expect(actual).to eq expected
  end
end

RSpec.shared_examples "requires Premium license" do
  it "returns an error" do
    allow(License).to receive(:premium?).and_return(false)

    expect_graphql_error(
      result: subject,
      message: "forbidden"
    )
    expect(License).to have_received(:premium?)
  end
end

RSpec.shared_examples "requires a customer portal user" do
  it "requires a customer portal user" do
    expect(described_class.ancestors).to include(AuthenticableCustomerPortalUser)
  end
end

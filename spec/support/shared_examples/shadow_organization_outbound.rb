# frozen_string_literal: true

RSpec.shared_examples "refused on a shadow organization" do |model|
  %w[shadowing paused].each do |status|
    context "when the organization is the shadow of a #{status} migration" do
      before { create(:billing_engine_migration, organization: create(:organization), shadow_organization: organization, status:) }

      it "refuses with shadow_organization_outbound_disabled" do
        expect { subject }.not_to change(model, :count)

        expect(subject).to be_failure
        expect(subject.error).to be_a(BaseService::ForbiddenFailure)
        expect(subject.error.code).to eq("shadow_organization_outbound_disabled")
      end
    end
  end

  context "when the organization is the shadow of an aborted migration" do
    before { create(:billing_engine_migration, organization: create(:organization), shadow_organization: organization, status: "aborted") }

    it { expect(subject).to be_success }
  end

  context "when the organization is the source of a migration" do
    before { create(:billing_engine_migration, organization:) }

    it { expect(subject).to be_success }
  end
end

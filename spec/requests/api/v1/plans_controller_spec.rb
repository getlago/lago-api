# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::PlansController, type: :request do
  let(:tax) { create(:tax, organization:) }
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, code: 'plan_code') }

  describe 'POST /api/v1/plans' do
    subject { post_with_token(organization, '/api/v1/plans', {plan: create_params}) }

    let(:create_params) do
      {
        name: 'P1',
        invoice_display_name: 'P1 invoice name',
        code: 'plan_code',
        interval:,
        description: 'description',
        amount_cents: 100,
        amount_currency: 'EUR',
        trial_period: 1,
        pay_in_advance: false,
        minimum_commitment: {
          amount_cents: 1000,
          invoice_display_name: 'Minimum commitment'
        },
        charges: [
          {
            billable_metric_id: billable_metric.id,
            charge_model: 'standard',
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: 'invoice',
            properties: {
              amount: '0.22'
            },
            tax_codes:
          }
        ],
        usage_thresholds: [
          amount_cents: 100,
          threshold_display_name: 'Threshold 1'
        ]
      }
    end
    let(:tax_codes) { [tax.code] }

    context 'when interval is empty' do
      let(:interval) { nil }

      it 'returns an error' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details]).to eq({interval: %w[value_is_mandatory]})
        end
      end
    end

    context 'when interval is present' do
      let(:interval) { 'weekly' }

      include_examples 'requires API permission', 'plan', 'write'

      it 'creates a plan' do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:plan][:lago_id]).to be_present
        expect(json[:plan][:code]).to eq(create_params[:code])
        expect(json[:plan][:name]).to eq(create_params[:name])
        expect(json[:plan][:invoice_display_name]).to eq(create_params[:invoice_display_name])
        expect(json[:plan][:created_at]).to be_present
        expect(json[:plan][:charges].first[:lago_id]).to be_present
      end

      context 'when license is not premium' do
        it 'ignores premium fields' do
          subject

          expect(response).to have_http_status(:success)
          charge = json[:plan][:charges].first
          expect(charge[:invoiceable]).to be true
          expect(charge[:regroup_paid_fees]).to be_nil
        end
      end

      context 'when license is premium' do
        around { |test| lago_premium!(&test) }

        it 'updates premium fields' do
          subject

          expect(response).to have_http_status(:success)
          charge = json[:plan][:charges].first
          expect(charge[:invoiceable]).to be false
          expect(charge[:regroup_paid_fees]).to eq 'invoice'
        end
      end

      context 'with minimum commitment' do
        context 'when license is premium' do
          around { |test| lago_premium!(&test) }

          it 'creates a plan with minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment][:lago_id]).to be_present
          end
        end

        context 'when license is not premium' do
          it 'does not create minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment]).not_to be_present
          end
        end
      end

      context 'with usage thresholds' do
        context 'when license is premium' do
          around { |test| lago_premium!(&test) }

          context 'when progressive billing premium integration is present' do
            before do
              organization.update!(premium_integrations: ['progressive_billing'])
            end

            it 'creates a plan with usage thresholds' do
              subject

              expect(response).to have_http_status(:success)
              expect(json[:plan][:usage_thresholds].first[:lago_id]).to be_present
              expect(json[:plan][:usage_thresholds].first[:amount_cents]).to eq(json[:plan][:amount_cents])
            end
          end

          context 'when progressive billing premium integration is not present' do
            it 'does not create usage thresholds' do
              subject

              expect(response).to have_http_status(:success)
              expect(json[:plan][:usage_thresholds].count).to eq(0)
            end
          end
        end

        context 'when license is not premium' do
          it 'does not create usage thresholds' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:usage_thresholds].count).to eq(0)
          end
        end
      end

      context 'with graduated charges' do
        let(:create_params) do
          {
            name: 'P1',
            code: 'plan_code',
            interval: 'weekly',
            description: 'description',
            amount_cents: 100,
            amount_currency: 'EUR',
            trial_period: 1,
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: billable_metric.id,
                charge_model: 'graduated',
                properties: {
                  graduated_ranges: [
                    {
                      to_value: 1,
                      from_value: 0,
                      flat_amount: '0',
                      per_unit_amount: '0'
                    },
                    {
                      to_value: nil,
                      from_value: 2,
                      flat_amount: '0',
                      per_unit_amount: '3200'
                    }
                  ]
                }
              }
            ]
          }
        end

        it 'creates a plan' do
          subject

          expect(response).to have_http_status(:success)

          expect(json[:plan][:lago_id]).to be_present
          expect(json[:plan][:code]).to eq(create_params[:code])
          expect(json[:plan][:name]).to eq(create_params[:name])
          expect(json[:plan][:created_at]).to be_present
          expect(json[:plan][:charges].first[:lago_id]).to be_present
        end
      end

      context 'without charges' do
        let(:create_params) do
          {
            name: 'P1',
            code: 'plan_code',
            interval: 'weekly',
            description: 'description',
            amount_cents: 100,
            amount_currency: 'EUR',
            trial_period: 1,
            pay_in_advance: false
          }
        end

        it 'creates a plan' do
          subject

          expect(response).to have_http_status(:success)

          expect(json[:plan][:lago_id]).to be_present
          expect(json[:plan][:code]).to eq(create_params[:code])
          expect(json[:plan][:name]).to eq(create_params[:name])
          expect(json[:plan][:created_at]).to be_present
          expect(json[:plan][:charges].count).to eq(0)
        end
      end

      context 'with unknown tax code on charge' do
        let(:tax_codes) { ['unknown'] }

        it 'returns a 404 response' do
          subject

          aggregate_failures do
            expect(response).to have_http_status(:not_found)
            expect(json[:error]).to eq('Not Found')
            expect(json[:code]).to eq('tax_not_found')
          end
        end
      end
    end
  end

  describe 'PUT /api/v1/plans/:code' do
    subject do
      put_with_token(
        organization,
        "/api/v1/plans/#{plan_code}",
        {plan: update_params}
      )
    end

    let(:minimum_commitment) { create(:commitment, plan:) }
    let(:plan) { create(:plan, organization:) }
    let(:plan_code) { plan.code }
    let(:code) { 'plan_code' }
    let(:tax_codes) { [tax.code] }

    let(:update_params) do
      {
        name: 'P1',
        code:,
        interval: 'weekly',
        description: 'description',
        amount_cents: 100,
        amount_currency: 'EUR',
        trial_period: 1,
        pay_in_advance: false,
        charges: charges_params,
        usage_thresholds: usage_thresholds_params
      }
    end

    let(:usage_thresholds_params) do
      [
        {
          amount_cents: 7_000,
          amount_currency: 'EUR',
          threshold_display_name: 'Updated threshold'
        }
      ]
    end

    let(:charges_params) do
      [
        {
          billable_metric_id: billable_metric.id,
          charge_model: 'standard',
          properties: {
            amount: '0.22'
          },
          tax_codes:
        }
      ]
    end

    let(:minimum_commitment_params) do
      {
        minimum_commitment: {
          amount_cents: 5000,
          invoice_display_name: 'Minimum commitment updated'
        }
      }
    end

    include_examples 'requires API permission', 'plan', 'write'

    it 'updates a plan' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:lago_id]).to eq(plan.id)
      expect(json[:plan][:code]).to eq(update_params[:code])
    end

    context 'when plan does not exist' do
      let(:plan_code) { SecureRandom.uuid }

      it 'returns not_found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when plan code already exists in organization scope (validation error)' do
      let(:other_org_plan) { create(:plan, organization:) }
      let(:code) { other_org_plan.code }

      it 'returns unprocessable_entity error' do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when license is not premium' do
      let(:charges_params) do
        [
          {
            billable_metric_id: billable_metric.id,
            charge_model: 'standard',
            properties: {
              amount: '0.22'
            },
            tax_codes:,
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: 'invoice'
          }
        ]
      end

      it 'ignores premium fields' do
        subject

        expect(response).to have_http_status(:success)
        charge = json[:plan][:charges].first
        expect(charge[:pay_in_advance]).to be true
        expect(charge[:invoiceable]).to be true
        expect(charge[:regroup_paid_fees]).to be_nil
      end
    end

    context 'when license is premium' do
      let(:charges_params) do
        [
          {
            billable_metric_id: billable_metric.id,
            charge_model: 'standard',
            properties: {
              amount: '0.22'
            },
            tax_codes:,
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: 'invoice'
          }
        ]
      end

      around { |test| lago_premium!(&test) }

      before { organization.update!(premium_integrations: ['progressive_billing']) }

      it 'updates premium fields' do
        subject

        expect(response).to have_http_status(:success)
        charge = json[:plan][:charges].first
        expect(charge[:pay_in_advance]).to be true
        expect(charge[:invoiceable]).to be false
        expect(charge[:regroup_paid_fees]).to eq 'invoice'

        usage_threshold = json[:plan][:usage_thresholds].first
        expect(usage_threshold[:amount_cents]).to eq(7_000)
      end
    end

    context 'when plan has no minimum commitment' do
      context 'when request contains minimum commitment params' do
        before { update_params.merge!(minimum_commitment_params) }

        context 'when license is premium' do
          around { |test| lago_premium!(&test) }

          it 'creates minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment][:amount_cents])
              .to eq(update_params[:minimum_commitment][:amount_cents])
          end
        end

        context 'when license is not premium' do
          it 'does not create minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment]).to be_nil
          end
        end
      end

      context 'when request does not contain minimum commitment params' do
        context 'when license is premium' do
          around { |test| lago_premium!(&test) }

          it 'does not create minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment]).to be_nil
          end
        end

        context 'when license is not premium' do
          it 'does not create minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment]).to be_nil
          end
        end
      end
    end

    context 'when plan has one minimum commitment' do
      before { minimum_commitment }

      context 'when request contains minimum commitment params' do
        before { update_params.merge!(minimum_commitment_params) }

        context 'when minimum commitment params are an empty hash' do
          let(:minimum_commitment_params) { {minimum_commitment: {}} }

          context 'when license is premium' do
            around { |test| lago_premium!(&test) }

            it 'deletes minimum commitment' do
              subject

              expect(response).to have_http_status(:success)
              expect(json[:plan][:minimum_commitment]).to be_nil
            end
          end

          context 'when license is not premium' do
            it 'does not delete the minimum commitment' do
              subject

              expect(response).to have_http_status(:success)
              expect(json[:plan][:minimum_commitment][:amount_cents]).to eq(minimum_commitment.amount_cents)
            end
          end
        end

        context 'when minimum commitment params are not an empty hash' do
          context 'when license is premium' do
            around { |test| lago_premium!(&test) }

            it 'updates minimum commitment' do
              subject

              expect(response).to have_http_status(:success)
              expect(json[:plan][:minimum_commitment][:amount_cents])
                .to eq(update_params[:minimum_commitment][:amount_cents])
            end
          end

          context 'when license is not premium' do
            it 'does not update minimum commitment' do
              subject

              expect(response).to have_http_status(:success)
              expect(json[:plan][:minimum_commitment][:amount_cents]).to eq(minimum_commitment.amount_cents)
            end
          end
        end
      end

      context 'when request does not contain minimum commitment params' do
        context 'when license is premium' do
          around { |test| lago_premium!(&test) }

          it 'does not update minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment][:amount_cents]).to eq(minimum_commitment.amount_cents)
          end
        end

        context 'when license is not premium' do
          it 'does not update minimum commitment' do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:plan][:minimum_commitment][:amount_cents]).to eq(minimum_commitment.amount_cents)
          end
        end
      end
    end
  end

  describe 'GET /api/v1/plans/:code' do
    subject { get_with_token(organization, "/api/v1/plans/#{plan_code}") }

    let(:plan) { create(:plan, organization:) }
    let(:plan_code) { plan.code }

    include_examples 'requires API permission', 'plan', 'read'

    it 'returns a plan' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan][:lago_id]).to eq(plan.id)
      expect(json[:plan][:code]).to eq(plan.code)
    end

    context 'when plan has minimum commitment' do
      before { create(:commitment, plan:) }

      it 'returns a plan' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan][:lago_id]).to eq(plan.id)
        expect(json[:plan][:code]).to eq(plan.code)
        expect(json[:plan][:minimum_commitment][:lago_id]).to eq(plan.minimum_commitment.id)
      end
    end

    context 'when plan has usage thresholds' do
      before do
        create(:usage_threshold, plan:)
        create(:usage_threshold, :recurring, plan:)
      end

      it 'returns a plan' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan][:lago_id]).to eq(plan.id)
        expect(json[:plan][:code]).to eq(plan.code)
        expect(json[:plan][:usage_thresholds].count).to eq(2)
      end
    end

    context 'when plan does not exist' do
      let(:plan_code) { SecureRandom.uuid }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/plans/:code' do
    subject { delete_with_token(organization, "/api/v1/plans/#{plan_code}") }

    let(:plan) { create(:plan, organization:) }
    let(:plan_code) { plan.code }

    include_examples 'requires API permission', 'plan', 'write'

    context 'when plan exists' do
      it 'marks plan as pending_deletion' do
        expect { subject }.to change { plan.reload.pending_deletion }.from(false).to(true)
      end

      it 'marks children plan as pending_deletion' do
        children_plan = create(:plan, parent_id: plan.id)

        expect { subject }
          .to change { children_plan.reload.pending_deletion }.from(false).to(true)
      end

      it 'returns deleted plan' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan][:lago_id]).to eq(plan.id)
        expect(json[:plan][:code]).to eq(plan.code)
      end
    end

    context 'when plan does not exist' do
      let(:plan_code) { SecureRandom.uuid }

      it 'returns not_found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/plans' do
    subject { get_with_token(organization, '/api/v1/plans?page=1&per_page=1') }

    let(:plan) { create(:plan, organization:) }

    before { create(:usage_threshold, plan:) }

    include_examples 'requires API permission', 'plan', 'read'

    it 'returns plans' do
      subject

      expect(response).to have_http_status(:success)

      expect(json[:plans].count).to eq(1)
      expect(json[:plans].first[:lago_id]).to eq(plan.id)
      expect(json[:plans].first[:code]).to eq(plan.code)
      expect(json[:plans].first[:usage_thresholds].count).to eq(1)
    end

    context "when pending for deletion plan exists" do
      subject { get_with_token(organization, "/api/v1/plans") }

      let(:plan_pending_for_deletion) do
        create(:plan, organization:, pending_deletion: true)
      end

      before { plan_pending_for_deletion }

      it "includes the plan in the response" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:plans].count).to eq(2)
        expect(json[:plans].map { |p| p[:lago_id] }).to include(plan_pending_for_deletion.id)
      end
    end

    context 'with pagination' do
      before { create(:plan, organization:) }

      it 'returns plans with correct meta data' do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:plans].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end
end

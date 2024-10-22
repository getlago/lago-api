# frozen_string_literal: true

class DunningCampaignsQuery < BaseQuery
  DEFAULT_ORDER = "name"

  def call
    dunning_campaigns = base_scope.result
    dunning_campaigns = paginate(dunning_campaigns)
    dunning_campaigns = dunning_campaigns.order(order)

    dunning_campaigns = with_applied_to_organization(dunning_campaigns) unless filters.applied_to_organization.nil?
    dunning_campaigns = with_currency_threshold(dunning_campaigns) if filters.currency.present?

    result.dunning_campaigns = dunning_campaigns
    result
  end

  private

  def base_scope
    DunningCampaign.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  def order
    DunningCampaign::ORDERS.include?(@order) ? @order : DEFAULT_ORDER
  end

  def with_applied_to_organization(scope)
    scope.where(applied_to_organization: filters.applied_to_organization)
  end

  def with_currency_threshold(scope)
    scope
      .joins(:thresholds)
      .where(dunning_campaign_thresholds: {currency: filters.currency})
      .distinct
  end
end

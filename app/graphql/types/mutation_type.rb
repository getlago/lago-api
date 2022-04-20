# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :login_user, mutation: Mutations::LoginUser
    field :register_user, mutation: Mutations::RegisterUser

    field :create_billable_metric, mutation: Mutations::BillableMetrics::Create
    field :update_billable_metric, mutation: Mutations::BillableMetrics::Update
    field :destroy_billable_metric, mutation: Mutations::BillableMetrics::Destroy

    field :create_plan, mutation: Mutations::Plans::Create
    field :update_plan, mutation: Mutations::Plans::Update
    field :destroy_plan, mutation: Mutations::Plans::Destroy

    field :create_customer, mutation: Mutations::Customers::Create
    field :update_customer, mutation: Mutations::Customers::Update
    field :destroy_customer, mutation: Mutations::Customers::Destroy

    field :create_subscription, mutation: Mutations::Subscriptions::Create
    field :terminate_subscription, mutation: Mutations::Subscriptions::Terminate
  end
end

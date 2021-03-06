# frozen_string_literal: true

require "spec_helper"

feature "Shops caching", js: true, caching: true do
  include WebHelper
  include UIComponentHelper

  let!(:distributor) { create(:distributor_enterprise, with_payment_and_shipping: true, is_primary_producer: true) }
  let!(:order_cycle) { create(:open_order_cycle, distributors: [distributor], coordinator: distributor) }

  describe "API action caching on taxons and properties" do
    let!(:taxon) { create(:taxon, name: "Cached Taxon") }
    let!(:taxon2) { create(:taxon, name: "New Taxon") }
    let!(:property) { create(:property, presentation: "Cached Property") }
    let!(:property2) { create(:property, presentation: "New Property") }
    let!(:product) { create(:product, taxons: [taxon], primary_taxon: taxon, properties: [property]) }
    let(:exchange) { order_cycle.exchanges.to_enterprises(distributor).outgoing.first }

    let(:test_domain) { "#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}" }
    let(:taxons_key) { "views/#{test_domain}/api/order_cycles/#{order_cycle.id}/taxons?distributor=#{distributor.id}" }
    let(:properties_key) { "views/#{test_domain}/api/order_cycles/#{order_cycle.id}/properties?distributor=#{distributor.id}" }
    let(:options) { { expires_in: CacheService::FILTERS_EXPIRY } }

    before do
      exchange.variants << product.variants.first
    end

    it "caches rendered response for taxons and properties, with the provided options" do
      visit enterprise_shop_path(distributor)

      expect(page).to have_content "Cached Taxon"
      expect(page).to have_content "Cached Property"

      expect_cached taxons_key, options
      expect_cached properties_key, options
    end

    it "keeps data cached for a short time on subsequent requests" do
      # One minute ago...
      Timecop.travel(Time.zone.now - 1.minute) do
        visit enterprise_shop_path(distributor)

        expect(page).to have_content taxon.name
        expect(page).to have_content property.presentation

        product.update_attribute(:taxons, [taxon2])
        product.update_attribute(:primary_taxon, taxon2)
        product.update_attribute(:properties, [property2])

        visit enterprise_shop_path(distributor)

        expect(page).to have_content taxon.name # Taxon list is unchanged
        expect(page).to have_content property.presentation # Property list is unchanged
      end

      # A while later...
      visit enterprise_shop_path(distributor)

      expect(page).to have_content taxon2.name
      expect(page).to have_content property2.presentation
    end
  end

  def expect_cached(key, options = {})
    expect(Rails.cache.exist?(key, options)).to be true
  end
end

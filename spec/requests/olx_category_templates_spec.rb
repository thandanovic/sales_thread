require 'rails_helper'

RSpec.describe "OlxCategoryTemplates", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/olx_category_templates/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /new" do
    it "returns http success" do
      get "/olx_category_templates/new"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get "/olx_category_templates/edit"
      expect(response).to have_http_status(:success)
    end
  end

end

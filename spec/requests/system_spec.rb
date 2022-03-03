require "rails_helper"

RSpec.describe "System checks", type: :request do
  describe "GET /ping" do
    it "returns http success and text response" do
      get "/ping"
      expect(response).to have_http_status(:success)
      expect(response.body).to eq "pong"
    end
  end
end

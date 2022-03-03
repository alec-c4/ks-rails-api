class SystemController < ApplicationController
  def ping
    render plain: "pong"
  end
end

# name: discourse-speedreader
# about: Word-by-word (RSVP) PDF speed reader — upload a PDF, read it one word at a time, resume where you left off.
# version: 0.1.0
# authors: Donát (Vaperina)
# url: https://github.com/VaperinaDEV/discourse-speedreader
# required_version: 2.7.0

enabled_site_setting :speedreader_enabled

register_asset "stylesheets/speedreader.scss"

after_initialize do
  module ::DiscourseSpeedreader
    PLUGIN_NAME = "discourse-speedreader"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseSpeedreader
    end
  end

  require_relative "app/models/speedreader_book"
  require_relative "app/models/speedreader_progress"
  require_relative "app/controllers/discourse_speedreader/books_controller"

  DiscourseSpeedreader::Engine.routes.draw do
    get "/books" => "books#index"
    post "/books" => "books#create"
    get "/books/:id" => "books#show"
    delete "/books/:id" => "books#destroy"
    put "/books/:id/progress" => "books#update_progress"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseSpeedreader::Engine, at: "/speedreader"
  end
end

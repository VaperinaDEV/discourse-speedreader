module DiscourseSpeedreader
  class BooksController < ::ApplicationController
    requires_login
    requires_plugin DiscourseSpeedreader::PLUGIN_NAME

    def index
      books = SpeedreaderBook.where(user_id: current_user.id).order(created_at: :desc)
      progress_by_book = SpeedreaderProgress.where(user_id: current_user.id).index_by(&:book_id)

      render json: {
        books: books.map { |b| book_summary_json(b, progress_by_book[b.id]) },
      }
    end

    def create
      uploaded = params[:file] || params[:pdf]
      raise Discourse::InvalidParameters.new(:file) if uploaded.blank?

      max_upload_bytes = SiteSetting.speedreader_max_upload_size_mb.megabytes
      if uploaded.size.to_i > max_upload_bytes
        return render_json_error(
          I18n.t("speedreader.errors.file_too_large", mb: SiteSetting.speedreader_max_upload_size_mb),
          status: 413,
        )
      end

      words = safe_json_array(params[:words])
      pages = safe_json_array(params[:pages])

      if words.size < 20
        return render_json_error(I18n.t("speedreader.errors.no_text_extracted"), status: 422)
      end
      if words.size > SiteSetting.speedreader_max_words_per_book
        return render_json_error(
          I18n.t("speedreader.errors.too_many_words", max: SiteSetting.speedreader_max_words_per_book),
          status: 413,
        )
      end

      upload = UploadCreator.new(uploaded.tempfile, uploaded.original_filename, type: "speedreader")
                             .create_for(current_user.id)
      unless upload.persisted?
        return render_json_error(upload.errors.full_messages.join(", "), status: 422)
      end

      # derive a title by stripping any extension
      filename = uploaded.original_filename.to_s
      title_guess = params[:title].presence || filename.sub(/\.[^.]+\z/, "")

      book = SpeedreaderBook.create!(
        user_id: current_user.id,
        title: title_guess,
        author: params[:author].presence,
        page_count: params[:page_count].to_i,
        word_count: words.size,
        upload_id: upload.id,
        words: words,
        pages: pages
      )

      render json: { book: book_summary_json(book, nil).except(:progress) }, status: 201
    end

    def show
      book = find_owned_book!
      progress = SpeedreaderProgress.find_by(user_id: current_user.id, book_id: book.id)

      render json: {
        book: book_summary_json(book, progress).except(:progress),
        words: book.words,
        pages: book.pages,
        progress: {
          word_index: progress&.word_index || 0,
          wpm: progress&.wpm || SiteSetting.speedreader_default_wpm,
          font_size: progress&.font_size || 2.6,
        },
      }
    end

    def destroy
      book = find_owned_book!
      book.destroy!
      render json: success_json
    end

    def update
      book = find_owned_book!
      updated = false
    
      if params[:title]
        book.title = params[:title].to_s.strip[0, 200]
        updated = true
      end
    
      if params[:author]
        book.author = params[:author].to_s.strip[0, 200]
        updated = true
      end
    
      if updated
        book.save!
      end
    
      render json: { book: book_summary_json(book, SpeedreaderProgress.find_by(user_id: current_user.id, book_id: book.id)) }
    end

    def update_progress
      book = find_owned_book!
      max_index = [book.word_count - 1, 0].max
      min_wpm = SiteSetting.speedreader_min_wpm
      max_wpm = SiteSetting.speedreader_max_wpm

      progress = SpeedreaderProgress.find_or_initialize_by(user_id: current_user.id, book_id: book.id)
      progress.word_index = params[:word_index].to_i.clamp(0, max_index)
      progress.wpm = params[:wpm].to_i.clamp(min_wpm, max_wpm)
      if params[:font_size]
        progress.font_size = params[:font_size].to_f.clamp(1.0, 4.0)
      end
      progress.save!

      render json: success_json
    end

    private

    def find_owned_book!
      book = SpeedreaderBook.find_by(id: params[:id], user_id: current_user.id)
      raise Discourse::NotFound unless book
      book
    end

    def safe_json_array(raw)
      parsed = JSON.parse(raw.to_s)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end

    def book_summary_json(book, progress)
      word_count = book.word_count.to_i
      word_index = progress&.word_index || 0
      percent = word_count > 0 ? ((word_index.to_f / word_count) * 1000).round / 10.0 : 0

      {
        id: book.id,
        title: book.title,
        author: book.author,
        page_count: book.page_count,
        word_count: word_count,
        created_at: book.created_at,
        progress: {
          word_index: word_index,
          wpm: progress&.wpm || SiteSetting.speedreader_default_wpm,
          percent: percent,
        },
      }
    end
  end
end

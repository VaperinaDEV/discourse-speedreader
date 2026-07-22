import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { service } from "@ember/service";
import { LinkTo } from "@ember/routing";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import dIcon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { extractFile } from "../lib/speedreader-file";

export default class SpeedreaderLibrary extends Component {
  @service siteSettings;

  @tracked books = this.args.model.books;
  @tracked uploading = false;
  @tracked uploadStatusText = "";
  @tracked errorMessage = null;

  get hasBooks() {
    return this.books && this.books.length > 0;
  }

  @action
  async onFileSelected(event) {
    const file = event.target.files[0];
    event.target.value = "";
    if (!file) return;

    const maxBytes = (this.siteSettings.speedreader_max_upload_size_mb || 80) * 1024 * 1024;
    if (file.size > maxBytes) {
      this.errorMessage = i18n("speedreader.errors.file_too_large", {
        mb: this.siteSettings.speedreader_max_upload_size_mb,
      });
      return;
    }

    this.errorMessage = null;
    this.uploading = true;
    this.uploadStatusText = i18n("speedreader.library.uploading", { percent: 0 });

    let extracted;
    try {
      extracted = await extractFile(file, (ratio, page, total) => {
        this.uploadStatusText = i18n("speedreader.library.processing", { page, total });
      });
    } catch (e) {
      console.error("Speedreader extraction error", e);
      this.errorMessage = this.extractionErrorMessage(e);
      this.uploading = false;
      return;
    }

    try {
      const formData = new FormData();
      // send as 'file' so controller can handle arbitrary formats
      formData.append("file", file);
      formData.append("words", JSON.stringify(extracted.words));
      formData.append("pages", JSON.stringify(extracted.pages));
      formData.append("page_count", extracted.numPages);
      if (extracted.title) formData.append("title", extracted.title);
      if (extracted.author) formData.append("author", extracted.author);

      await ajax("/speedreader-api/books", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false,
      });

      const { books } = await ajax("/speedreader-api/books");
      this.books = books;
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.uploading = false;
    }
  }

  extractionErrorMessage(e) {
    const msg = e && e.message;
    if (msg === "unsupported-format") return i18n("speedreader.errors.unsupported_format");
    if (msg === "not-a-docx-file") return i18n("speedreader.errors.invalid_docx");
    if (msg === "not-an-epub-file" || msg === "epub-missing-opf") {
      return i18n("speedreader.errors.invalid_epub");
    }
    if (msg === "jszip-load-failed") return i18n("speedreader.errors.jszip_load_failed");
    if (msg === "no-text-found") return i18n("speedreader.errors.no_text_extracted_client");
    return i18n("speedreader.errors.no_text_extracted_client");
  }

  @action
  async deleteBook(book) {
    if (!window.confirm(i18n("speedreader.library.delete_confirm"))) return;
    try {
      await ajax(`/speedreader-api/books/${book.id}`, { type: "DELETE" });
      this.books = this.books.filter((b) => b.id !== book.id);
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async editTitle(book) {
    const newTitle = window.prompt(i18n("speedreader.library.edit_title_prompt"), book.title || "");
    if (!newTitle) return;
    try {
      const resp = await ajax(`/speedreader-api/books/${book.id}`, {
        type: "PUT",
        data: { title: newTitle.trim().slice(0, 200) },
      });
      // update local list
      if (resp && resp.book) {
        this.books = this.books.map((b) => (b.id === book.id ? { ...b, title: resp.book.title } : b));
      } else {
        this.books = this.books.map((b) => (b.id === book.id ? { ...b, title: newTitle } : b));
      }
    } catch (e) {
      popupAjaxError(e);
    }
  }

  <template>
    <div class="speedreader">
      <div class="sr-upload-row">
        <label class="btn btn-primary" for="speedreader-pdf-input">
          {{i18n "speedreader.library.upload_button"}}
        </label>
        <input
          type="file"
          id="speedreader-pdf-input"
          accept="application/pdf,.pdf,.epub,.docx,.txt,.md,.markdown"
          hidden
          {{on "change" this.onFileSelected}}
        />
        {{#if this.uploading}}
          <span class="sr-upload-status">{{this.uploadStatusText}}</span>
        {{/if}}
      </div>

      {{#if this.errorMessage}}
        <div class="alert alert-error">{{this.errorMessage}}</div>
      {{/if}}

      {{#if this.hasBooks}}
        <div class="sr-book-grid">
          {{#each this.books as |book|}}
            <div class="sr-book-card">
              <div class="sr-book-info">
                <h3>{{book.title}}</h3>
                {{#if book.author}}<div class="sr-book-author">{{book.author}}</div>{{/if}}
                <div class="sr-book-meta">
                  {{i18n "speedreader.library.words_count" count=book.word_count}}
                  ·
                  {{i18n "speedreader.library.pages_count" count=book.page_count}}
                </div>
              </div>
              <div class="sr-book-actions">
                <LinkTo @route="speedreader-reader" @model={{book.id}} class="btn btn-primary">
                  {{#if book.progress.word_index}}
                    {{i18n "speedreader.library.continue_reading"}}
                  {{else}}
                    {{i18n "speedreader.library.start_reading"}}
                  {{/if}}
                </LinkTo>
                <button
                  type="button"
                  class="btn btn-icon no-text"
                  {{on "click" (fn this.editTitle book)}}
                >
                  {{dIcon "pencil"}}
                </button>
                <button
                  type="button"
                  class="btn btn-danger"
                  {{on "click" (fn this.deleteBook book)}}
                >
                  {{i18n "speedreader.library.delete"}}
                </button>
              </div>
            </div>
          {{/each}}
        </div>
      {{else}}
        <p class="sr-empty">{{i18n "speedreader.library.empty"}}</p>
      {{/if}}
    </div>
  </template>
}

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { LinkTo } from "@ember/routing";
import { ajax } from "discourse/lib/ajax";
import dIcon from "discourse/helpers/d-icon";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { i18n } from "discourse-i18n";

const SENTENCE_END_RE = /[.!?…]$/;

export default class SpeedreaderReader extends Component {
  @service siteSettings;

  words = this.args.model.words;
  pages = this.args.model.pages;

  @tracked book = this.args.model.book;
  @tracked displayUnits = [];
  @tracked dIdx = 0;
  @tracked playing = false;
  @tracked wpm =
    this.args.model.progress.wpm || this.siteSettings.speedreader_default_wpm || 300;
  @tracked chunkMode = false;
  @tracked justSaved = false;
  @tracked fontSize = parseFloat(this.args.model.progress.font_size) || 2.6;

  // track which page index is selected in the UI so the <select> follows playback
  @tracked selectedPageIndex = 0;

  // editing title state
  @tracked editingTitle = false;
  @tracked editTitleValue = "";

  // reference to the root DOM element, set via did-insert
  element = null;

  timer = null;
  saveTimer = null;
  dragging = false;

  constructor() {
    super(...arguments);
    this.buildDisplayUnits();
    const startWordIndex = this.args.model.progress.word_index || 0;
    this.dIdx = this.displayIndexFor(startWordIndex);

    // initialize selected page based on startWordIndex
    this.updateSelectedPage();

    // initialize editTitleValue
    this.editTitleValue = this.book.title || "";

    this._onKeyDown = this.onKeyDown.bind(this);
    this._onMouseMove = this.onFuseDrag.bind(this);
    this._onMouseUp = this.onFuseDragEnd.bind(this);
    window.addEventListener("keydown", this._onKeyDown);
    window.addEventListener("mousemove", this._onMouseMove);
    window.addEventListener("mouseup", this._onMouseUp);
  }

  willDestroy() {
    super.willDestroy(...arguments);
    clearTimeout(this.timer);
    clearTimeout(this.saveTimer);
    window.removeEventListener("keydown", this._onKeyDown);
    window.removeEventListener("mousemove", this._onMouseMove);
    window.removeEventListener("mouseup", this._onMouseUp);
    this.saveProgress(true);
  }

  @action
  setupElement(el) {
    this.element = el;
    // ensure font size is within allowed bounds and apply it
    const applied = Math.min(4.0, Math.max(1.0, +this.fontSize));
    this.fontSize = applied;
    el.style.setProperty('--sr-font-size', `${this.fontSize}rem`);
  }

  @action
  teardownElement() {
    this.element = null;
  }

  @action
  startEditTitle() {
    this.editingTitle = true;
    this.editTitleValue = this.book.title || "";
    // focus handled by browser; optional autofocus could be added
  }

  @action
  onTitleInput(event) {
    this.editTitleValue = event.target.value;
  }
  
  @action
  onTitleKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.saveTitle();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelEditTitle();
    }
  }

  @action
  cancelEditTitle() {
    this.editingTitle = false;
  }

  @action
  async saveTitle() {
    const title = String(this.editTitleValue || "").trim().slice(0, 200);
    try {
      const resp = await ajax(`/speedreader-api/books/${this.book.id}`, {
        type: "PUT",
        data: { title },
      });
      const newTitle = (resp && resp.book && resp.book.title) ? resp.book.title : title;
      this.book = { ...this.book, title: newTitle };
      this.editingTitle = false;
    } catch (e) {
      console.error('Failed to save title', e);
      alert(i18n('speedreader.errors.save_failed'));
    }
  }

  get chunkWordsList() {
    const raw = this.siteSettings.speedreader_chunk_words;
    if (Array.isArray(raw)) return raw;
    if (typeof raw === "string") return raw.split("|").filter(Boolean);
    return [];
  }

  buildDisplayUnits() {
    const words = this.words;
    if (!this.chunkMode) {
      this.displayUnits = words.map((w, i) => ({ text: w, start: i }));
      return;
    }
    const shortSet = new Set(this.chunkWordsList.map((w) => w.toLowerCase()));
    const out = [];
    for (let i = 0; i < words.length; i++) {
      const w = words[i];
      const bare = w.toLowerCase().replace(/[^\p{L}]/gu, "");
      if (shortSet.has(bare) && w.length <= 4 && i + 1 < words.length) {
        out.push({ text: w + " " + words[i + 1], start: i });
        i++;
      } else {
        out.push({ text: w, start: i });
      }
    }
    this.displayUnits = out;
    // after rebuilding units, ensure the selected page still follows the current index
    this.updateSelectedPage();
  }

  displayIndexFor(wordIdx) {
    const units = this.displayUnits;
    let lo = 0;
    let hi = units.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (units[mid].start <= wordIdx) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  }

  get currentUnit() {
    return this.displayUnits[this.dIdx] || { text: "", start: 0 };
  }

  get currentWordIndex() {
    return this.currentUnit.start;
  }

  get pivotSplit() {
    const word = this.currentUnit.text;
    const len = word.length;
    let p;
    if (len <= 1) p = 0;
    else if (len <= 3) p = 1;
    else if (len <= 7) p = 2;
    else if (len <= 11) p = 3;
    else p = 4;
    p = Math.min(p, len - 1);
    return {
      before: word.slice(0, p),
      pivot: word.slice(p, p + 1),
      after: word.slice(p + 1),
    };
  }

  get totalWords() {
    return this.words.length;
  }

  get progressPercent() {
    return this.totalWords > 1 ? (this.currentWordIndex / (this.totalWords - 1)) * 100 : 0;
  }

  get fuseFillStyle() {
    return htmlSafe(`width: ${this.progressPercent}%`);
  }

  get fuseSparkStyle() {
    return htmlSafe(`left: ${this.progressPercent}%`);
  }

  get wordsProgressText() {
    return i18n("speedreader.reader.words_progress", {
      current: this.currentWordIndex + 1,
      total: this.totalWords,
    });
  }

  get timeRemainingText() {
    const remaining = this.totalWords - this.currentWordIndex - 1;
    const secs = Math.max(0, Math.round((remaining * 60) / this.wpm));
    const mm = Math.floor(secs / 60);
    const ss = String(secs % 60).padStart(2, "0");
    return i18n("speedreader.reader.time_remaining", { time: `${mm}:${ss}` });
  }

  delayForUnit(text) {
    const base = 60000 / this.wpm;
    let mult = 1;
    const len = text.length;
    if (len > 6) mult += Math.min(0.7, (len - 6) * 0.04);
    const last = text[len - 1];
    if (".!?…".includes(last)) mult *= 2.3;
    else if (",;:—-".includes(last)) mult *= 1.55;
    if (text === text.toUpperCase() && /[A-ZÁÉÍÓÖŐÚÜŰ]/.test(text) && len > 1) mult *= 1.3;
    return base * mult;
  }

  scheduleNext() {
    clearTimeout(this.timer);
    if (!this.playing) return;
    if (this.dIdx >= this.displayUnits.length - 1) {
      this.pause();
      this.saveProgress(true);
      return;
    }
    const unit = this.displayUnits[this.dIdx];
    this.timer = setTimeout(() => {
      this.dIdx = this.dIdx + 1;
      // update selected page whenever we advance
      this.updateSelectedPage();
      this.scheduleNext();
    }, this.delayForUnit(unit.text));
  }

  @action
  play() {
    if (this.dIdx >= this.displayUnits.length - 1) this.dIdx = 0;
    this.playing = true;
    this.scheduleNext();
  }

  @action
  pause() {
    this.playing = false;
    clearTimeout(this.timer);
    this.saveProgress();
  }

  @action
  togglePlay() {
    this.playing ? this.pause() : this.play();
  }

  seekToWordIndex(newIdx) {
    const clamped = Math.max(0, Math.min(this.totalWords - 1, newIdx));
    this.dIdx = this.displayIndexFor(clamped);
    // ensure the select follows the new index
    this.updateSelectedPage();
    if (this.playing) this.scheduleNext();
  }

  @action
  jumpWordBack() {
    this.pause();
    this.seekToWordIndex(this.currentWordIndex - 1);
  }
  
  @action
  jumpWordForward() {
    this.pause();
    this.seekToWordIndex(this.currentWordIndex + 1);
  }

  @action
  jumpSentenceBack() {
    this.pause();
    let i = this.currentWordIndex;
    i = Math.max(0, i - 1);
    while (i > 0 && !SENTENCE_END_RE.test(this.words[i - 1])) i--;
    this.seekToWordIndex(i);
  }
  
  @action
  jumpSentenceForward() {
    this.pause();
    let i = this.currentWordIndex;
    while (i < this.totalWords - 1 && !SENTENCE_END_RE.test(this.words[i])) i++;
    i = Math.min(i + 1, this.totalWords - 1);
    this.seekToWordIndex(i);
  }

  @action
  onWpmInput(event) {
    const min = this.siteSettings.speedreader_min_wpm || 100;
    const max = this.siteSettings.speedreader_max_wpm || 900;
    this.wpm = Math.max(min, Math.min(max, parseInt(event.target.value, 10)));
    this.saveProgress();
  }

  @action
  onChunkToggle(event) {
    this.pause();
    const wordIdx = this.currentWordIndex;
    this.chunkMode = event.target.checked;
    this.buildDisplayUnits();
    this.dIdx = this.displayIndexFor(wordIdx);
    // ensure page select updates after chunk mode change
    this.updateSelectedPage();
  }

  @action
  onPageSelect(event) {
    // event.target.value is a page index (word index to jump to)
    const idx = parseInt(event.target.value, 10);
    this.pause();
    this.seekToWordIndex(idx);
  }

  @action
  onFuseMouseDown(event) {
    this.dragging = true;
    this.seekFromClientX(event.clientX);
  }

  onFuseDrag(event) {
    if (this.dragging) this.seekFromClientX(event.clientX);
  }

  onFuseDragEnd() {
    if (this.dragging) {
      this.dragging = false;
      this.saveProgress(true);
    }
  }

  seekFromClientX(clientX) {
    const track = document.querySelector(".speedreader .sr-fuse-track");
    if (!track) return;
    const rect = track.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    this.pause();
    this.seekToWordIndex(Math.round(ratio * (this.totalWords - 1)));
  }

  increaseFontStep(step = 0.2) {
    const min = 1.0;
    const max = 4.0;
    this.fontSize = Math.min(max, +(this.fontSize + step).toFixed(2));
    if (this.element) this.element.style.setProperty('--sr-font-size', `${this.fontSize}rem`);
  }

  decreaseFontStep(step = 0.2) {
    const min = 1.0;
    const max = 4.0;
    this.fontSize = Math.max(min, +(this.fontSize - step).toFixed(2));
    if (this.element) this.element.style.setProperty('--sr-font-size', `${this.fontSize}rem`);
  }

  @action
  increaseFont() {
    this.increaseFontStep();
    this.saveProgress();
  }

  @action
  decreaseFont() {
    this.decreaseFontStep();
    this.saveProgress();
  }

  onKeyDown(event) {
    if (event.target.tagName === "SELECT" || event.target.tagName === "INPUT") return;
    const min = this.siteSettings.speedreader_min_wpm || 100;
    const max = this.siteSettings.speedreader_max_wpm || 900;

    if (event.code === "Space") {
      event.preventDefault();
      this.togglePlay();
    } else if (event.code === "ArrowLeft") {
      event.preventDefault();
      this.jumpWordBack();
    } else if (event.code === "ArrowRight") {
      event.preventDefault();
      this.jumpWordForward();
    } else if (event.code === "ArrowUp") {
      event.preventDefault();
      this.wpm = Math.min(max, this.wpm + 25);
      this.saveProgress();
    } else if (event.code === "ArrowDown") {
      event.preventDefault();
      this.wpm = Math.max(min, this.wpm - 25);
      this.saveProgress();
    } else if (event.key === "+" || event.key === "=") {
      event.preventDefault();
      this.increaseFont();
    } else if (event.key === "-") {
      event.preventDefault();
      this.decreaseFont();
    }
  }

  saveProgress(immediate) {
    clearTimeout(this.saveTimer);
    const doSave = () => {
      ajax(`/speedreader-api/books/${this.book.id}/progress`, {
        type: "PUT",
        data: { word_index: this.currentWordIndex, wpm: this.wpm, font_size: this.fontSize },
      })
        .then(() => {
          this.justSaved = true;
          setTimeout(() => (this.justSaved = false), 1400);
        })
        .catch(() => {});
    };
    if (immediate) doSave();
    else this.saveTimer = setTimeout(doSave, 800);
  }

  updateSelectedPage() {
    if (!Array.isArray(this.pages) || this.pages.length === 0) {
      this.selectedPageIndex = 0;
      return;
    }
    // find the last page entry whose index <= currentWordIndex
    let found = null;
    for (let i = this.pages.length - 1; i >= 0; i--) {
      if (this.pages[i].index <= this.currentWordIndex) {
        found = this.pages[i];
        break;
      }
    }
    if (!found) found = this.pages[0];
    this.selectedPageIndex = found.index;
  }

  <template>
    <div class="speedreader" {{didInsert this.setupElement}} {{willDestroy this.teardownElement}}>
      <div class="sr-topbar">
        <LinkTo @route="speedreader-library" class="sr-back-link">
          {{i18n "speedreader.reader.back_to_library"}}
        </LinkTo>
        <div class="sr-book-title">
          {{#if this.editingTitle}}
            <input
              class="sr-title-input"
              type="text"
              value={{this.editTitleValue}}
              {{on "input" this.onTitleInput}}
              {{on "keydown" this.onTitleKeyDown}}
            />
            <button
              type="button"
              class="btn btn-primary btn-icon no-text"
              {{on "click" this.saveTitle}}
            >
              {{dIcon "check"}}
            </button>
            <button
              type="button"
              class="btn btn-default btn-icon no-text"
              {{on "click" this.cancelEditTitle}}
            >
              {{dIcon "xmark"}}
            </button>
          {{else}}
            <div class="sr-editable-title">
              <h1>{{this.book.title}}</h1>
              <button
                type="button"
                class="btn btn-transparent btn-small btn-icon no-text"
                {{on "click" this.startEditTitle}}
              >
                {{dIcon "pencil"}}
              </button>
            </div>
          {{/if}}
          {{#if this.book.author}}
            <div class="sr-book-author">{{this.book.author}}</div>
          {{/if}}
        </div>
        <select value={{this.selectedPageIndex}} {{on "change" this.onPageSelect}}>
          {{#each this.pages as |pm|}}
            <option value={{pm.index}}>{{pm.page}}</option>
          {{/each}}
        </select>
      </div>

      <div class="sr-stage">
        <div class="sr-guide sr-guide-top"></div>
        <div class="sr-word-row">
          <span class="sr-word-before">{{this.pivotSplit.before}}</span><span
            class="sr-word-pivot"
          >{{this.pivotSplit.pivot}}</span><span class="sr-word-after">{{this.pivotSplit.after}}</span>
        </div>
        <div class="sr-guide sr-guide-bottom"></div>
        <div class="sr-meta-row">
          <span>{{this.wordsProgressText}}</span>
          <span>{{this.timeRemainingText}}</span>
        </div>
      </div>

      <div class="sr-fuse-wrap">
        <div class="sr-fuse-track" {{on "mousedown" this.onFuseMouseDown}}>
          <div class="sr-fuse-fill" style={{this.fuseFillStyle}}></div>
          <div class="sr-fuse-spark" style={{this.fuseSparkStyle}}></div>
        </div>
      </div>

      <div class="sr-controls">
        <button
          type="button"
          class="sr-btn-round"
          {{on "click" this.jumpSentenceBack}}
        >
          {{dIcon "angles-left"}}
        </button>
        <button
          type="button"
          class="sr-btn-round"
          {{on "click" this.jumpWordBack}}
        >
          {{dIcon "angle-left"}}
        </button>
        <button
          type="button"
          class="sr-btn-play"
          {{on "click" this.togglePlay}}
        >
          {{#if this.playing}}
            {{dIcon "pause"}}
          {{else}}
            {{dIcon "play"}}
          {{/if}}
        </button>
        <button
          type="button"
          class="sr-btn-round"
          {{on "click" this.jumpWordForward}}
        >
          {{dIcon "angle-right"}}
        </button>
        <button
          type="button"
          class="sr-btn-round"
          {{on "click" this.jumpSentenceForward}}
        >
          {{dIcon "angles-right"}}
        </button>
      </div>

      <div class="sr-panel-row">
        <div class="sr-speed-block">
          <label>{{i18n "speedreader.reader.speed_label"}}</label>
          <input
            type="range"
            min={{this.siteSettings.speedreader_min_wpm}}
            max={{this.siteSettings.speedreader_max_wpm}}
            step="10"
            value={{this.wpm}}
            {{on "input" this.onWpmInput}}
          />
          <span class="sr-speed-value">{{this.wpm}}
            {{i18n "speedreader.reader.wpm_unit"}}</span>
        </div>
        <label class="sr-toggle-row">
          <input type="checkbox" checked={{this.chunkMode}} {{on "change" this.onChunkToggle}} />
          {{i18n "speedreader.reader.chunk_toggle"}}
        </label>
        <div class="sr-size-controls">
          <button
            type="button"
            class="btn btn-icon no-text"
            {{on "click" this.decreaseFont}}
          >
            {{dIcon "minus"}}
          </button>
          <div class="sr-size-value">{{this.fontSize}}rem</div>
          <button
            type="button"
            class="btn btn-primary btn-icon no-text"
            {{on "click" this.increaseFont}}
          >
            {{dIcon "plus"}}
          </button>
        </div>
      </div>

      <div class="sr-hint-row">
        {{#if this.justSaved}}{{i18n "speedreader.reader.position_saved"}}{{/if}}
      </div>

      <div class="sr-key-hints">
        Space: {{i18n "speedreader.reader.key_play"}} · {{dIcon "arrow-left"}}/{{dIcon "arrow-right"}}: 1 · {{dIcon "arrow-up"}}/{{dIcon "arrow-down"}}: WPM · {{dIcon "plus"}}/{{dIcon "minus"}}: {{i18n "speedreader.reader.key_font"}}
      </div>
    </div>
  </template>
}

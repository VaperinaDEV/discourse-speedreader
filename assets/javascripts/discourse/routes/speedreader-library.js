import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class SpeedreaderLibraryRoute extends DiscourseRoute {
  async model() {
    return ajax("/speedreader/books");
  }
}

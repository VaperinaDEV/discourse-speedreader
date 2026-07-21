import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class SpeedreaderReaderRoute extends DiscourseRoute {
  async model(params) {
    return ajax(`/speedreader/books/${params.book_id}`);
  }
}

import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class SpeedreaderReaderRoute extends DiscourseRoute {
  async model(params) {
    return ajax(`/speedreader-api/books/${params.book_id}`);
  }
}

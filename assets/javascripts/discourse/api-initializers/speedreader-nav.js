import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  api.addCommunitySectionLink({
    name: "speedreader",
    route: "speedreader-library",
    title: i18n("speedreader.nav_label"),
    text: i18n("speedreader.nav_label"),
    icon: "book-open",
  });
});

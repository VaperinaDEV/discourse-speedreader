export default function () {
  this.route("speedreader-library", { path: "/speedreader" });
  this.route("speedreader-reader", { path: "/speedreader/read/:book_id" });
}

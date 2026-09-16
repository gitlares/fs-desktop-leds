const desk = document.querySelector(".desk-preview");
const colors = [...document.querySelectorAll("[data-color]")];

for (const button of colors) {
  button.addEventListener("click", () => {
    desk.style.setProperty("--light", button.dataset.color);
    for (const choice of colors) {
      choice.setAttribute("aria-pressed", String(choice === button));
    }
  });
}

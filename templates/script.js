
const menuButton = document.getElementById("menuButton");
const navigation = document.getElementById("navigation");
const headerActions = document.querySelector(".header-actions");

menuButton.addEventListener("click", () => {
    navigation.classList.toggle("active");
    headerActions.classList.toggle("active");
});

document.querySelectorAll(".navigation a").forEach(link => {
    link.addEventListener("click", () => {
        navigation.classList.remove("active");
        headerActions.classList.remove("active");
    });
});

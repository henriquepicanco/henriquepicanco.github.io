var funciona = document.querySelector(".funciona");

funciona.addEventListener("click", funcionaSim);

function funcionaSim() {
	funciona.innerHTML = "O script funciona perfeitamente!"
	funciona.disabled = true;
}

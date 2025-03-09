package main

import (
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/table"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"gopkg.in/yaml.v3"
)

type User struct {
	FirstName  string                 `yaml:":first_name"`
	LastName   string                 `yaml:":last_name"`
	Klasse     string                 `yaml:":klasse"`
	Geburtstag string                 `yaml:":geburtstag"`
	Roles      map[string]interface{} `yaml:":roles"`
	Alter	   int
}

// Model represents the state of the application.
type model struct {
	width        int
	height       int
	textInput    textinput.Model
	output       []string
	autocomplete []string
	table        table.Model
	command      string
}

// Initial command to fetch autocomplete suggestions (simulated here).
func fetchAutocomplete() tea.Cmd {
	return func() tea.Msg {
		// Simulate fetching autocomplete suggestions.
		return []string{"help", "exit", "clear", "list", "search"}
	}
}

// Init initializes the application.
func (m model) Init() tea.Cmd {
	return fetchAutocomplete()
}

// Update handles input and updates the model.
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	if m.command == "add" {
		m.textInput, cmd = m.textInput.Update(msg)
	}
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		// Handle window resize events.
		m.width = msg.Width
		m.height = msg.Height
		m.table.SetWidth(msg.Width - 4)
		m.table.SetHeight(msg.Height - 3)
	case tea.KeyMsg:
		switch msg.String() {
		case "esc":
			if m.command == "add" {
				m.command = ""
				m.textInput.Reset()
				m.textInput.Blur()
			}
			break
		case "ctrl+c":
			// Quit the application.
			return m, tea.Quit
		case "enter":
			// Handle command input.
			command := m.textInput.Value()
			m.output = append(m.output, fmt.Sprintf("> %s", command))
			m.textInput.Reset()

			switch command {
			case "clear":
				m.output = nil
				break
			case "list":
				// Simulate loading data into the table.
				break

			}
		case "a":
			m.command = "add"
			m.textInput.Focus()
			break

		case "tab":
			// Handle autocomplete.
			input := m.textInput.Value()
			for _, suggestion := range m.autocomplete {
				if strings.HasPrefix(suggestion, input) {
					m.textInput.SetValue(suggestion)
					break
				}
			}
		}
	case []string:
		// Update autocomplete suggestions.
		m.autocomplete = msg
	}

	// Update the text input.
	m.table, _ = m.table.Update(msg)
	return m, cmd
}

// View renders the UI.
func (m model) View() string {
	// Define styles.
	style := lipgloss.NewStyle().
		Width(m.width-2).
		Height(m.height-4).
		Margin(0).
		Padding(0, 1).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62"))

	// Render output.
	// output := strings.Join(m.output, "\n")

	// Combine output and input.
	return style.Render(fmt.Sprintf(
		"%s",
		m.table.View(),
	)) + "\n[H] Hinzufügen   [E] Eingetroffen   [A] Abholung   [N] Nimmt mit"

}

func main() {
	yaml_path := "../../../internal/debug/@@user_info.yaml"
	data, err := os.ReadFile(yaml_path)
	if err != nil {
		log.Fatalf("Failed to read YAML file: %v", err)
	}

	// Parse the YAML file into a map of users.
	var users map[string]User
	if err := yaml.Unmarshal(data, &users); err != nil {
		log.Fatalf("Failed to parse YAML: %v", err)
	}

	var schueler = map[string]User{}

	// Iterate over the users and filter those with the ":teacher" role.
	for email, user := range users {
		if hasSchuelerRole(user.Roles) {
			schueler[email] = user
		}
	}

	// Initialize the text input.
	ti := textinput.New()
	ti.Placeholder = "Add person..."

	// Initialize the table.
	columns := []table.Column{
		{Title: "Nachname", Width: 20},
		{Title: "Vorname", Width: 20},
		{Title: "Klasse", Width: 6},
		{Title: "Alter", Width: 5},
	}

	rows := []table.Row{
	}

	for _, user := range schueler {
		birthDate, err := time.Parse("2006-01-02", user.Geburtstag)
		if err != nil {
			log.Fatalf("Failed to parse Geburtstag: %v", err)
		}
		age := time.Now().Year() - birthDate.Year()
		if time.Now().YearDay() < birthDate.YearDay() {
			age--
		}
		user.Alter = age
		rows = append(rows, table.Row{
			user.LastName,
			user.FirstName,
			user.Klasse,
			fmt.Sprintf("%d", user.Alter),
		})
	}

	// Sort the rows by Klasse, LastName, FirstName.
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i][2] == rows[j][2] {
			if rows[i][0] == rows[j][0] {
				return rows[i][1] < rows[j][1]
			}
			return rows[i][0] < rows[j][0]
		}
		return rows[i][2] < rows[j][2]
	})


	t := table.New(
		table.WithColumns(columns),
		table.WithRows(rows),
		table.WithFocused(true),
	)

	// Initialize the model.
	initialModel := model{
		textInput: ti,
		autocomplete: []string{},
		table: t,
	}

	// Start the Bubble Tea program.
	p := tea.NewProgram(initialModel, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
	}
}

func hasSchuelerRole(roles map[string]interface{}) bool {
	if rolesHash, ok := roles["hash"].(map[string]interface{}); ok {
		if schueler, ok := rolesHash[":schueler"].(bool); ok {
			return schueler
		}
	}
	return false
}

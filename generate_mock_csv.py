import csv
import random

def generate_mock_csv(filename, num_rows=10):
    headers = [
        "First Name", "Last Name", "Email Address", "Employee ID", 
        "Phone Number", "Dept", "Location", "Job Title", "Weight"
    ]
    
    first_names = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Heidi", "Ivan", "Judy", "Mallory", "Niaj"]
    last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez"]
    departments = ["Engineering", "HR", "Sales", "Marketing", "Finance", "Legal"]
    locations = ["New York", "London", "Tokyo", "Remote", "Berlin"]
    titles = ["Manager", "Engineer", "Director", "Analyst", "Coordinator"]
    
    with open(filename, mode='w', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        writer.writerow(headers)
        
        for i in range(num_rows):
            fn = random.choice(first_names)
            ln = random.choice(last_names)
            email = f"{fn.lower()}.{ln.lower()}{i}@example.com"
            emp_id = f"EMP{1000 + i}"
            phone = f"555-{random.randint(100, 999)}-{random.randint(1000, 9999)}"
            dept = random.choice(departments)
            loc = random.choice(locations)
            title = random.choice(titles)
            weight = round(random.uniform(1.0, 5.0), 1)
            
            writer.writerow([fn, ln, email, emp_id, phone, dept, loc, title, weight])
            
        # Add a couple of error rows for testing the wizard
        writer.writerow(["Bad", "User", "not-an-email", "ERR1", "", "", "", "", "1.0"])
        writer.writerow(["Missing", "Email", "", "ERR2", "", "", "", "", "1.0"])

if __name__ == "__main__":
    generate_mock_csv("test_members.csv", 8)
    print("Created test_members.csv with 8 valid rows and 2 error rows.")

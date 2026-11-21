import javax.swing.*;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;

public class Main {
    // public and String[] args required for this to work
    public static void main(String[] args) {
        // Basic window
        JFrame window = new JFrame("Hello World");
        this.setLocationRelativeTo(null);
        this.setDefaultCloseOperation(JFrame.DO_NOTHING_ON_CLOSE);

        this.setResizable(false);
        this.setVisible(true);
    }
}
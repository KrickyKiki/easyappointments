<?php defined('BASEPATH') or exit('No direct script access allowed');

/* ----------------------------------------------------------------------------
 * Easy!Appointments - Online Appointment Scheduler
 *
 * @package     EasyAppointments
 * @author      A.Tselegidis <alextselegidis@gmail.com>
 * @copyright   Copyright (c) Alex Tselegidis
 * @license     https://opensource.org/licenses/GPL-3.0 - GPLv3
 * @link        https://easyappointments.org
 * @since       v1.4.0
 * ---------------------------------------------------------------------------- */

class Migration_Add_book_advance_timeout_column_to_services_table extends EA_Migration
{
    /**
     * Upgrade method.
     */
    public function up()
    {
        if (!$this->db->field_exists('book_advance_timeout', 'services')) {
            $fields = [
                'book_advance_timeout' => [
                    'type' => 'INT',
                    'null' => false,
                    'default' => 30,
                    'after' => 'price',
                ],
            ];

            $this->dbforge->add_column('services', $fields);
        }
    }

    /**
     * Downgrade method.
     */
    public function down()
    {

        if ($this->db->field_exists('book_advance_timeout', 'services')) {
            $this->dbforge->drop_column('services', 'book_advance_timeout');
        }
    }
}
